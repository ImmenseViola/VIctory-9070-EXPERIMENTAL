# VIctory-9070 — EXPERIMENTAL

> **EXPERIMENTAL FORK. NOT THE TUNED MAIN TREE.**
> The tuned tree in `VIctory-7900XTX` and its `main` branch are untouched.
> Nothing here is a release. Do not merge back until the user has visual-tested
> a full-length visible run and approved it.

- Repo: <https://github.com/ImmenseViola/VIctory-9070-EXPERIMENTAL>
- Working branch: `experimental/texture-pass-aside`
- GitHub root: `main` is mirrored from the working branch so the repo is not
  empty; `experimental/texture-pass-aside` is where work lands first.
- Baseline: the tuned tree as of `5d784e3`.

## Why this exists

The tuned build is host-bound in dense views, not VRAM-bandwidth-bound. The
card is only ~55–61% busy and sits idle while the submitting thread prepares
descriptor/refreshes/copies. The heap-texture pass is one of the remaining
inline costs (roughly 7–10 ms in dense views).

The eventual goal is moving that work aside. A direct
`aside::begin(heap_textures)` move is **unsafe**: `State::heap_textures`
records D3D commands into the title's list and needs a much larger ahead-job
refactor. So this fork tests small, read-side cuts first, one switch at a time,
without touching the tuned tree.

## Current default

`VICTORY_TEX_VIEW_CACHE` is **enabled by default in this fork**. This is
intentional: the fork exists to carry the experiment. Set
`VICTORY_TEX_VIEW_CACHE=0` to restore the tuned tree's read-every-time
behaviour, or use `VICTORY_AB` to compare both sides in one run.

## Switches

| Switch | Default here | A/B name | Status |
|---|---|---|---|
| `VICTORY_TEX_VIEW_CACHE` | **on** | `VICTORY_TEX_VIEW_CACHE` | Clean dense A/B win; pending user visual check |
| `VICTORY_TEX_SKIP_NOVIEW` | off | `VICTORY_TEX_SKIP_NOVIEW` | Built and tested; no game A/B yet |

A switch named in `VICTORY_AB=<seconds>,<name>` no longer follows its own
environment value; the A/B phases decide it.

### `VICTORY_TEX_VIEW_CACHE`

In `crates/victory-gpu/src/draw.rs`, `State::heap_textures` used to read the
same descriptor many times for one due slot — `heap.handle(index)` up to ten
times and `heap.handle(index).and_then(descriptor::view)` several more. With
this switch, each due slot lazily caches one handle and one raw view, then
reuses them for the rest of that slot.

Unchanged:

- `host.mirror`, `texture_slot_*`, `ahead::take/send`, and `readable` are still
  called at the same points and in the same order.
- No upload, barrier, refresh, or command-list ordering moves.
- No texture selection, budget, or lifetime change.

Risk: the title can write a descriptor while the texture pass runs, so a
cached raw view can be slightly older than a fresh read later in the same
slot. That is the only semantic change. It stays out of the tuned tree until
the user says the picture is clean.

### `VICTORY_TEX_SKIP_NOVIEW`

Off here too until it earns a place. After the room and residency gates, a due
slot whose raw view is a constant, sampler, console sampler, unordered view, or
unordered placed view is finished immediately instead of being mirrored and
then discarded a few lines later. Placed buffers and shader-resource views are
left on the old path because their mapped/title-written state may still
matter.

This is also read-side/early-exit only. It is built into
`target-exp2\diag\victory.exe`; `target-exp\diag\victory.exe` remains the
view-cache-only binary for the user's visual test.

## Game A/B protocol

- warmed cache `victory-7900-clean-cache-1`
- `VICTORY_LATE_WAIT=3`
- `VICTORY_AB=20,VICTORY_TEX_VIEW_CACHE`
- passive screen/motion/memory monitor
- watcher stops at phase 7 or 29.5 GB private and refuses to kill during
  shader/pipeline creation
- no manual input during automated runs

Full results are in `EXPERIMENT_LOG.md`.

## Build and run

```powershell
cd 'C:\Users\Admin\AppData\Local\Temp\opencode\VIctory-9070-EXPERIMENTAL'
$env:CARGO_TARGET_DIR='C:\Users\Admin\AppData\Local\Temp\opencode\VIctory-9070-EXPERIMENTAL\target-exp'
cargo test -p victory-gpu --features diagnostics
cargo build --locked --profile diag -p victory --features diagnostics
```

Quick start for user test play (view cache on by default, no input script):

```powershell
& 'C:\Users\Admin\AppData\Local\Temp\opencode\start-play-session.ps1' `
  -Tag texview-visual1 `
  -Binary 'C:\Users\Admin\AppData\Local\Temp\opencode\VIctory-9070-EXPERIMENTAL\target-exp\diag\victory.exe' `
  -Console series-x -Upscaler 6 `
  -Cache 'C:\Users\Admin\AppData\Local\Temp\opencode\victory-7900-clean-cache-1' `
  -Extra @{ VICTORY_CARD_BUFFERS_MIN_MB='1'; VICTORY_LATE_WAIT='3'; VICTORY_KEYS='' }
```

Local harness scripts used for these runs are copied into `tools/`; their
paths are machine-specific and meant to be edited.

## Promotion rule

Nothing here goes into the tuned tree until there is:

1. a clean dense matched A/B,
2. stable memory with no paging-crash frames, and
3. a user visual check for shimmer, flicker, missing textures, wrong floor
   colours, and face/eye artifacts.

The view cache has satisfied (1) and (2). It is waiting on (3).

## Next cuts, in order

1. `VICTORY_TEX_HOST_CACHE` — avoid a repeated `GetDesc`/`hosted()` and a
   second `placed_texture` per candidate. Expected 0.2–1 ms.
2. `VICTORY_TEX_QUEUE_BATCH` — coalesce host-slot mutex updates. Expected
   0.2–1.5 ms in backlog-heavy passes; `room` checks must stay in place.
3. Full heap-texture aside — only after an ahead-job refactor that can carry
   texture uploads and barriers safely.

Parallel filtering of live descriptor/title state is parked; it would change
which bytes upload.

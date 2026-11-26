# VIctory-9070 — EXPERIMENTAL

> **EXPERIMENTAL FORK. NOT THE TUNED MAIN TREE.**
> The tuned tree in `VIctory-9070` and its `main` branch are untouched.
> Nothing here is a release. Do not merge back until the user has visual-tested
> a full-length visible run and approved it.

- Repo: <https://github.com/ImmenseViola/VIctory-9070-EXPERIMENTAL>
- Working branch: `experimental/texture-pass-aside`
- GitHub root: `main` is mirrored from the working branch so the repo is not
  empty; `experimental/texture-pass-aside` is where work lands first.
- Baseline: the tuned tree as of `5d784e3`.

## Why this exists

The tuned build is host-bound in dense views, not VRAM-bandwidth-bound. The
card sits idle while the submitting thread prepares descriptor/refreshes/copies.
The heap-texture pass used to be one of the inline costs, which is why the view
cache was tried first. After that cache, dense series-S frames measure 51.6 ms
mean / 48.9 ms median: preparing takes 39.3 ms (copies 15.2 ms at ~51 MB/frame,
textures only 1.5 ms), copying back takes 10.5 ms at ~9 MB/frame, and the GPU
reports ~0.3 ms of wait. Reaching 30 fps means removing roughly 18 ms more, so
the next cuts target copy recording and copy-back, not the texture pass.

The long-term idea of moving the heap-texture pass aside is still parked: a
direct `aside::begin(heap_textures)` move is **unsafe** because
`State::heap_textures` records D3D commands into the title's list and needs a
much larger ahead-job refactor. This fork tests small, one-variable changes,
one at a time, without touching the tuned tree.

## Current default

`VICTORY_TEX_VIEW_CACHE` is **enabled by default in this fork**. This is
intentional: the fork exists to carry the experiment. Set
`VICTORY_TEX_VIEW_CACHE=0` to restore the tuned tree's read-every-time
behaviour, or use `VICTORY_AB` to compare both sides in one run.

## Switches

| Switch | Default here | A/B name | Status |
|---|---|---|---|
| `VICTORY_TEX_VIEW_CACHE` | **on** | `VICTORY_TEX_VIEW_CACHE` | Clean dense A/B win (mostly mean/p90, median only 1–3 ms); user visual check done, no cache-specific artifact seen |
| `VICTORY_TEX_SKIP_NOVIEW` | off | `VICTORY_TEX_SKIP_NOVIEW` | Built and unit-tested, but **not** a proven pure early exit: mirror work is skipped. A/B blocked pending the draw-time mirror-safety trace |

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
slot. That is the only semantic change. The user visual check found no new
artifact that could be blamed on it; the remaining bugs (vegetation popping,
black puddles/shorelines, car-light shimmer, driving dips) are the ones already
recorded in the tuned tree. It stays out of the tuned tree until a full-length
stable run is available — see the promotion rule below.

### `VICTORY_TEX_SKIP_NOVIEW`

Off here too until it earns a place. After the room and residency gates, a due
slot whose raw view is a constant, sampler, console sampler, unordered view, or
unordered placed view is finished immediately without calling
`host.mirror(index, handle, true)`. Placed buffers and shader-resource views
are left on the old path.

**This is not a proven pure early exit.** `host.mirror` builds the host
descriptor when the slot key changed, nulls or unmakes stale slots, and updates
buffer bookkeeping through `note_buffer`. On the old path those view kinds all
go through that work before `texture_slot_done`. Skipping it is only harmless
if every draw-time path that binds those slots mirrors them itself first;
otherwise stale samplers/UAVs could look like wrong filtering, flicker, or
corrupted compute output. A read-only trace of those paths is in progress, and
the game A/B is blocked until it is answered. It is built into
`target-exp2\diag\victory.exe`; `target-exp\diag\victory.exe` remains the
view-cache-only binary.

## Game A/B protocol

- warmed cache `victory-7900-clean-cache-1`
- `VICTORY_LATE_WAIT=3`
- `VICTORY_AB=20,VICTORY_TEX_VIEW_CACHE`
- passive screen/motion/memory monitor
- watcher stops at phase 7 or 29.5 GB private and refuses to kill during
  shader/pipeline creation
- no manual input during automated runs

Full results are in `EXPERIMENT_LOG.md`. The cache's win is mostly in the mean
(4.5–7.8 ms) and p90 (2.8–7.4 ms); medians moved only 1–3 ms, so it mainly
helps the worst frames rather than the typical one.

### User visual check (`texview-visual1`, series X)

The user played the default-on binary for about ten minutes. They could not
see an FPS difference by eye, but reported the same graphical bugs as the main
branch: vegetation popping in and out, black puddles/shorelines, falling FPS
while driving, and car lights popping/shimmering. Eyes looked better, but they
could not say whether that differs from the main branch. Nothing looked like
a new cache-specific regression. The run was stopped at 30.8 GB private with no
shader/pipeline work active; physical memory recovered afterwards.

A series-S manual comparison (`series-s-visual1`) found driving on quiet island
roads much more responsive, averaging in the 20s. Dense logged frames were
51.6 ms mean / 48.9 ms median, with 39.3 ms preparing (15.2 ms copies, 1.5 ms
textures) and 10.5 ms copying back. Vegetation was confirmed to fade with
distance, i.e. ordinary LOD/streaming rather than a new cache artifact. The
target is now 30 fps, so the next cut must remove several milliseconds of CPU
work, not sub-millisecond reads.

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
2. memory **no worse than the baseline** over the same scene/route — not an
   unrelated fix of the whole memory wall, and
3. a user visual check for shimmer, flicker, missing textures, wrong floor
   colours, and face/eye artifacts.

The view cache satisfies all three: it won the matched A/B, allocates nothing,
and the user found no new artifact. It is still kept out of the tuned tree only
because no full-length stable release has been validated yet. Private memory
reaching 29.7–30.8 GB on a 32 GB machine is a real, separate problem: it
probably causes some driving dips and may explain the vegetation fade. It is
tracked in `EXPERIMENT_LOG.md`, but it is not a reason to blame this cache.

## Next cuts, in order

Measured dense series-S frames spend 15.2 ms in copy recording and 10.5 ms in
copy-back, versus 1.5 ms in the texture pass. Even perfect texture cuts cannot
supply the ~18 ms needed for 30 fps, so the order is:

1. **Copy categories** — the host's ~51 MB/frame is mostly refresh work on a
   handful of large title buffers: a 50 MB buffer uploads ~7 MB/frame in ~160
   pieces, two 24 MB buffers another ~4 MB, and a 45 MB buffer is fetched at
   ~8 MB/frame. The bus actually moves ~13 MB up and ~13 MB back in ~50
   copies. Map those addresses to title heaps and test whether
   `port::place_for` can place any of them like renderer port 1 does for the
   32-bit graphics heap — stopping a whole category is worth more than
   shaving the remaining calls.
2. **Copy-back** — investigate why ~9 MB/frame costs 10.5 ms and cut the CPU
   side of that path without changing the read-back results.
3. `VICTORY_TEX_SKIP_NOVIEW` — only after the mirror-safety trace says it is
   harmless; then A/B it alone and combined with the view cache.
4. `VICTORY_TEX_HOST_CACHE` and `VICTORY_TEX_QUEUE_BATCH` — parked sub-ms
   texture cuts, not part of the 30 fps path.
5. Full heap-texture aside — only after an ahead-job refactor that can carry
   texture uploads and barriers safely.

Parallel filtering of live descriptor/title state is parked; it would change
which bytes upload.

## Local data safety

The working tree, logs, and warmed cache currently live under
`AppData\Local\Temp\opencode`. Windows Storage Sense can clear Temp, which
would lose the warmed version-3 cache and force a long recompile. Copy or move
the tree and cache to a permanent folder, and point the scripts in `tools/` at
it before relying on them.

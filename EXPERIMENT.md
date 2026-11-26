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

#### On/off unit test

`draw.rs::slot_view_tests` now drives the same `SlotViews` helper the pass uses
with a recorded heap: cache on and off are compared for every view kind the
pass handles, with both a present and an absent handle. One test asserts the two
paths see identical values on a stable slot while the cached path reads one
handle and one view; another records the known difference when the title
rewrites the descriptor mid-pass. This runs in CI, no device or game session
needed. It covers read changes only: a switch that also skips side effects needs
a separate host-side harness and stays blocked.

## Game A/B protocol

- warmed cache `victory-7900-clean-cache-1`
- `VICTORY_LATE_WAIT=3`
- `VICTORY_AB=20,VICTORY_TEX_VIEW_CACHE`
- passive screen/motion/memory monitor
- watcher stops at phase 7 or 29.5 GB private and refuses to kill during
  shader/pipeline creation
- no manual input during automated runs

The next one-variable run uses the same route with
`VICTORY_AB=20,VICTORY_HEAP_SYNC_EARLY`: dense frames spend ~10.4 ms at the
end of submission waiting for heap records, while the background round itself
costs only ~4.7 ms across all threads. It changes when the existing descriptor
round runs, not which bytes upload. Compare frame ms, the end-wait line,
private memory, then do a visual check before any default change.

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
cd 'C:\mygame\victory-work\VIctory-9070-EXPERIMENTAL'
$env:CARGO_TARGET_DIR='C:\mygame\victory-work\VIctory-9070-EXPERIMENTAL\target-exp'
cargo test -p victory-gpu --features diagnostics
cargo build --locked --profile diag -p victory --features diagnostics
```

Quick start for user test play (view cache on by default, no input script):

```powershell
& 'C:\mygame\victory-work\VIctory-9070-EXPERIMENTAL\tools\start-play-session.ps1' `
  -Tag texview-visual1 `
  -Binary 'C:\mygame\victory-work\VIctory-9070-EXPERIMENTAL\target-exp\diag\victory.exe' `
  -Console series-x -Upscaler 6 `
  -Cache 'C:\mygame\victory-work\victory-7900-clean-cache-1' `
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

1. **Copy recording** — the host's ~51 MB/frame is mostly refresh work on a
   handful of large title buffers: a 50 MB buffer uploads ~7 MB/frame in ~160
   pieces, two 24 MB buffers another ~4 MB, and a 45 MB buffer is fetched at
   ~8 MB/frame. The bus actually moves ~13 MB up and ~13 MB back in ~50
   copies. The dense log has ~7900 refresh spans per frame, ~6900 of them
   known to copy nothing, so gather/schedule cost dominates bytes. Do not
   simply place those big buffers in title memory: they sit above 4 GiB and
   `port::place_for` only covers the low 4 GiB graphics region; moving them
   would bring back PCIe-bound shader reads. Start at
   `host.rs::run_deferred` and `host.rs::Batch`, preserving copied bytes and
   every refresh's position relative to title and shader writes.
2. **Copy-back** — investigate why ~9 MB/frame costs 10.5 ms and cut the CPU
   side of that path without changing the read-back results.
3. `VICTORY_HEAP_SYNC_EARLY` — clean dense A/B done: the current early default
   was 47.55 ms mean / 45.9 ms median at 5,676 draws, against 49.5 ms / 48.0 ms
   with early rounds off. The end wait did not fall (9.9 ms off vs 10.8 ms on),
   so the mechanism is unconfirmed; no default change came from this run.
4. Parked sub-ms texture cuts — not part of the 30 fps path.
5. Full heap-texture aside — only after an ahead-job refactor that can carry
   texture uploads and barriers safely.

Parallel filtering of live descriptor/title state is parked; it would change
which bytes upload.

## Local data safety

The working tree and warmed cache live under `C:\mygame\victory-work`, outside
Temp, so Windows Storage Sense cannot clear the warmed version-3 cache. The
paths in this file and in `tools/README.md` point there. Historical play logs
remain under `AppData\Local\Temp\opencode` and are not needed to rebuild.

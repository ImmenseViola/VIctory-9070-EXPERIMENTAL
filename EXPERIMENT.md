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
| `VICTORY_REFRESH_FINE_JOBS` | off | `VICTORY_REFRESH_FINE_JOBS` | Cut 1a: one game run never reached gameplay and crashed; stays off |
| `VICTORY_WIDE_REFRESH_MORE` | off | `VICTORY_WIDE_REFRESH_MORE` | Cut 1b: first run black/idle; one retry confounded by scene mismatch; stays off |
| `VICTORY_WIDE_THREADS_MAX` | off (default helper count) | — | Fixed pool ceiling for cut 1b, not an A/B switch on its own |
| `VICTORY_PENDING_INDEX` | off | `VICTORY_PENDING_INDEX` | Cut 2 implemented, equivalence-tested, awaiting A/B |

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

### Cut 1a: `VICTORY_REFRESH_FINE_JOBS`

`host::fine_spans` cuts a refresh span into at most four jobs, never below
`256 KiB` a job, before the wide dispatch in `refresh_spans`, `refresh_ahead`,
and `flush_all`. It changes only which worker claims which bytes: the byte
union, span order, `ahead` marking, ask windows, and title-write boundaries are
unchanged. Off by default; named in `VICTORY_AB`, the phase decides it at every
present. `host.rs::tests::fine_refresh_jobs_have_the_same_bytes_in_the_same_order`
asserts identical bytes and order, including empty and short spans.

### Cut 1b: `VICTORY_WIDE_REFRESH_MORE`

`shadow::wide_threads()` still keeps three helpers on this machine. A fixed
`VICTORY_WIDE_THREADS_MAX` ceiling (default: the usual count) keeps extra idle
helpers alive; `VICTORY_WIDE_REFRESH_MORE=1` wakes them for each wide dispatch.
The atomic index counter still hands every number to exactly one claimer, so
only who does a piece changes. Off by default and A/B-able. Extra helpers wait
without spinning while off, and a raise wakes them before jobs are queued.
`shadow.rs::more_wide_tests::more_helpers_claim_the_same_work` asserts identical
index coverage for three, seven, and nine claimers. Both game A/Bs were
confounded: the first never left the black title screen, and the one allowed
retry reached gameplay only on the on side's visual samples (off-side luma gap
`28.3`, non-black gap `85.6` points) despite all frame deltas being draws. No
further retry is allowed and the switch stays off.

### Cut 2: `VICTORY_PENDING_INDEX`

`shadow::Pending` keeps the old `pending` vector authoritative and in insertion
order; a sorted `(start, end, position)` index with prefix maxima only answers
the overlap questions previously answered by linear scans. It is used by
`send_copied`, `writing`, `copy_back_done`, `writes_pending_in`,
`stale_under_writes`, `merge_under_writes`, `update`, and `nothing_new`. It does
not touch `Batch.ahead`, submission ordering, ask windows, or title-write
boundaries, and it has no cached skip decision. Off by default and A/B-able; a
query rebuilds from the vector whenever the index is absent or stale.

`shadow.rs::pending_index_tests` compares indexed answers with the old scans
for nested, touching, duplicate, and empty ranges, after every push and retain,
and over dense query ranges. It asserts identical overlap booleans, identical
insertion-order ranges after clipping, and identical byte gaps passed to the
copy functions.

## Game A/B protocol

- warmed cache `victory-7900-clean-cache-1`
- `VICTORY_LATE_WAIT=3`
- `VICTORY_AB=20,VICTORY_TEX_VIEW_CACHE`
- passive screen/motion/memory monitor
- watcher stops at phase 7 or 29.5 GB private and refuses to kill during
  shader/pipeline creation
- no manual input during automated runs
- Enter-only key schedule including world entry (`2/5/8/11/20/75/78:Enter`),
  no movement or camera keys, so matched phases share one scene; if translation
  outlasts the early presses, a later Enter-only window
  (`150-156/210-216/270:Enter`) is entry assistance, not a second cut variable

`VICTORY_AB=20,VICTORY_HEAP_SYNC_EARLY` is done: no regression, possible 1–2 ms,
mechanism unconfirmed and confounded by movement/frame differences. Early rounds
are already the default, so no action follows. The `VICTORY_COPY_STAGES=1`
breakdown has now been reported in `EXPERIMENT_LOG.md`: refresh flushes and
their `nothing_new` checks dominate "copies", and the copy-back residual
dominates "copying back". No optimisation has been chosen or written from it.

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

The submitting thread's 45 ms frame is 38 ms in submissions: lists' steps
18 ms (with 11.94 ms nested refresh and 9.89 ms caller wall), heap waits
8.65 ms, asking 4.17 ms, then smaller segments. It waits 0.35 ms on the relay
outside submissions and 0.00 ms inside them, so copy-back's 10.78 ms is real
CPU work but not the direct critical path. Even perfect texture cuts cannot
supply the ~15 ms needed for 30 fps, so the order is:

1. **Candidate A — per-shadow interval index plus per-flush span union** —
   attacks the 11.94 ms nested refresh and its 9.89 ms caller wall. Estimated
   0.5–1.5 ms, not yet proven. Start at `host.rs::run_deferred` and
   `host.rs::Batch`, preserving copied bytes and every refresh's position
   relative to title and shader writes. Do not place the big buffers in title
   memory: they sit above 4 GiB and `port::place_for` only covers the low 4 GiB
   graphics region, so moving them would reintroduce PCIe-bound shader reads.
2. **Heap-wait attribution** — a diagnostic before any cut. The 8.65 ms
   `begin_sync_heaps` wait is directly on the critical path, but why it waits
   is not yet known.
3. **Candidate B — incremental declared-range joining/ordering** — off the
   table for the direct 30 fps path. The submitter does not wait on the relay
   or landing; copy-back would only help indirectly through CPU contention.
4. **Pending-range-only copy-back** — off the table. Pending UAV writes cover
   38.44 of 38.44 MB compared, and 27.2% of those bytes really differ; there
   is nothing safe to skip.
5. `VICTORY_HEAP_SYNC_EARLY` — A/B done: no regression, possible 1–2 ms,
   mechanism unconfirmed. Early rounds are already the default, so no action.
   Future A/Bs use Enter-only after world entry.
6. Parked sub-ms texture cuts — not part of the 30 fps path.
7. Full heap-texture aside — only after an ahead-job refactor that can carry
   texture uploads and barriers safely.

Cuts 1a and 1b are implemented off by default and awaiting their own A/B runs.
Nothing is promoted to a default without a clean run and the user's visual
check.

Parallel filtering of live descriptor/title state is parked; it would change
which bytes upload.

## Local data safety

The working tree and warmed cache live under `C:\mygame\victory-work`, outside
Temp, so Windows Storage Sense cannot clear the warmed version-3 cache. The
paths in this file and in `tools/README.md` point there. Historical play logs
remain under `AppData\Local\Temp\opencode` and are not needed to rebuild.

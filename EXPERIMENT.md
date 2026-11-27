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
| `VICTORY_REFRESH_FINE_JOBS` | off | `VICTORY_REFRESH_FINE_JOBS` | Cut 1a: **dropped** after title crashes in both game runs; stays off and is not part of the next build's stack |
| `VICTORY_WIDE_REFRESH_MORE` | **on** | `VICTORY_WIDE_REFRESH_MORE` | Cut 1b: canonical fixed-view **no regression** (`-0.38/-0.35/-0.32 ms`, 24 pairs); enabled in frozen #2 as part of the combined stack; `=0` restores the old helper count |
| `VICTORY_WIDE_THREADS_MAX` | **6** | — | Fixed pool ceiling for 1b, matching the canonical combined run; `=3` restores the old ceiling; not an A/B switch on its own |
| `VICTORY_WIDE_HELPERS` | off (usual count) | — | Off-phase helper count for a scaling A/B (6 for 6-vs-8, 8 for 8-vs-10); not a switch |
| `VICTORY_WIDE_HELPERS_8` | off | `VICTORY_WIDE_HELPERS_8` | Dropped: 25 matched pairs, `0/0.1/0.09 ms`, **no regression**; scaling past six helpers does not pay |
| `VICTORY_WIDE_HELPERS_10` | off | `VICTORY_WIDE_HELPERS_10` | Conditional on 8 winning; not in frozen #2 |
| `VICTORY_PENDING_INDEX` | **on** | `VICTORY_PENDING_INDEX` | Cut 2: canonical fixed-view **no regression** (`0.17/0.12/-0.25 ms`, 25 pairs); enabled in frozen #2 as part of the combined stack; `=0` restores the old scan |
| `VICTORY_HEAP_SYNC_SAFE` | **on** | `VICTORY_HEAP_SYNC_SAFE` | Cut 3: fixed-view clean win (`-1.42/-1.22/-0.48 ms`, six pairs, draw deviation `0.3%`); enabled in frozen #2; `=0` restores the old wait |
| `VICTORY_HEAP_SYNC_EARLY` | on (4 ms) | `VICTORY_HEAP_SYNC_EARLY` | Existing A/B: off removes self-originated early rounds; retest under the fixed view before using it |
| `VICTORY_HEAP_SYNC_RUSH` | off | `VICTORY_HEAP_SYNC_RUSH` | Parked: small ceiling, no completed canonical A/B; unit-tested for byte/order equivalence but not in frozen #2 |

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

`host::fine_spans` cuts a refresh span into at most four jobs before the wide
dispatch in `refresh_spans`, `refresh_ahead`, and `flush_all`. Internal
boundaries are page-aligned, and 64 KiB-aligned where the span can hold pieces
that large; no piece is below 4 KiB unless the original span is shorter. It
changes only which worker claims which bytes: the byte union, span order,
`ahead` marking, ask windows, and title-write boundaries are unchanged. Off by
default; named in `VICTORY_AB`, the phase decides it at every present.
`host.rs::tests::fine_refresh_jobs_have_the_same_bytes_in_the_same_order`
asserts identical bytes and order, including empty and short spans;
`host.rs::tests::fine_refresh_jobs_are_page_aligned_and_do_not_share_pages`
asserts that no two jobs of one shadow touch the same 4 KiB page.

### Cut 1b: `VICTORY_WIDE_REFRESH_MORE`

`shadow::wide_threads()` still keeps three helpers on this machine. A fixed
`VICTORY_WIDE_THREADS_MAX` ceiling (default: six in this fork, matching the
canonical combined run) keeps three extra idle helpers alive;
`VICTORY_WIDE_REFRESH_MORE` wakes them for each wide dispatch. The atomic index
counter still hands every number to exactly one claimer, so only who does a
piece changes. The switch is **on by default in this fork** and remains A/B-able
and reversible with `VICTORY_WIDE_REFRESH_MORE=0`; a named `VICTORY_AB` switch
overrides both. Extra helpers wait without spinning while off, and a raise wakes
them before jobs are queued.
`shadow.rs::more_wide_tests::more_helpers_claim_the_same_work` asserts identical
index coverage for three, seven, and nine claimers. The canonical fixed-view run
was **no regression** (`-0.38/-0.35/-0.32 ms`, 24 pairs); the combined stack with
Cut 3 and Cut 2 was a clean win. The user accepted playability as the goal and
deferred visuals, so 1b is enabled in frozen binary #2.

### Cut 2: `VICTORY_PENDING_INDEX`

`shadow::Pending` keeps the old `pending` vector authoritative and in insertion
order; a sorted `(start, end, position)` index with prefix maxima only answers
the overlap questions previously answered by linear scans. It is used by
`send_copied`, `writing`, `copy_back_done`, `writes_pending_in`,
`stale_under_writes`, `merge_under_writes`, `update`, and `nothing_new`. It does
not touch `Batch.ahead`, submission ordering, ask windows, or title-write
boundaries, and it has no cached skip decision. It is **on by default in this
fork**, remains A/B-able, and `VICTORY_PENDING_INDEX=0` restores the old scans;
a query rebuilds from the vector whenever the index is absent or stale.

`shadow.rs::pending_index_tests` compares indexed answers with the old scans
for nested, touching, duplicate, and empty ranges, after every push and retain,
and over dense query ranges. It asserts identical overlap booleans, identical
insertion-order ranges after clipping, and identical byte gaps passed to the
copy functions. The earlier confounded/crashing run was superseded by the
canonical fixed-view run (`0.17/0.12/-0.25 ms`, 25 pairs, **no regression**) and
the combined clean win; Cut 2 is enabled in frozen binary #2.

### Cut 3: `VICTORY_HEAP_SYNC_SAFE`

`port_journal::on()` also accepts this switch, which is **on by default in this
fork** (`VICTORY_HEAP_SYNC_SAFE=0` restores the old wait). It makes
the same askers (`queue::behind`'s submit-time marks) and the same waiter
(`host`'s prepare-time `needed()`) use the existing mark path:
`descriptor::round_after_now()` asks a real heap-sync round earlier and the
mark is carried through `port_journal::set_mark`/`needed`. It does **not** turn
on renderer port #7's journal sharding; `watch::port_journal()` still controls
that separately.

Unchanged: `descriptor::Over::drop` is still the only event that advances a
round's `done`; timed early rounds still do not complete a caller's round;
`descriptor::SyncedHeaps::drop` is still the wait point; and `make_waiting()`
stays after that wait. No list bytes, submissions, waits, or round decisions
move.

`port_journal::tests::safe_heap_sync_uses_the_same_mark_decision` asserts that
with the switch off no mark is used, with it on the same mark/floor decision is
used as the old port #7 path while the journal sharding remains off, and that
`round_after(asked, done)` gives the same result in both states.

### Next heap-wait pieces after Cut 3

Cut 3 cut the end wait from `7.6–8.3 ms` to `3.4–3.7 ms` per frame, but the
saved time was largely spent in longer list/refresh work on the same side. The
residual is not page reads (`0 ms`): it is a round-completion wait. Dense on-side
frames ask about `8` rounds and find about `18` already asked per frame, while
the sync thread's own 4 ms early rounds (`VICTORY_HEAP_SYNC_EARLY`) can sit just
ahead of a submission's round.

The remaining A/B-able follow-ups are parked, not in frozen binary #2:

1. `VICTORY_HEAP_SYNC_EARLY=0` changes round timing/snapshot: fewer
   self-originated rounds run, so an asked round can start at once. Bytes and
   submission order stay unchanged, and `Over::drop` remains the only completion
   event. Its earlier game A/B was confounded by movement/frame changes.
2. `VICTORY_HEAP_SYNC_RUSH` gives the one round a submit waits for the fine job
   shape (`SYNC_PAGES_FINE`, `SYNC_AT_A_TIME_FINE`) instead of the usual
   early-round shape. `take_rush_round` gives the shape to only the first round
   that starts after the ask, then clears the mark. The records mirrored, their
   order, the wait point and the completion point are unchanged.
   `rush_chunks_cover_the_same_records_in_order` and `rush_round_is_taken_once`
   cover the invariants. The user parked it: the ceiling looks small, and its
   canonical A/B was stopped before completion.

Do not spend the next build on the late-round or prep-write fallbacks: both log
`0` in the dense phases.

### Helper-count scaling: dropped

Cut 1b's earlier two-pair win did not replicate in the canonical fixed-view run
(mean `-0.38 ms`, label **no regression**). The canonical
`VICTORY_WIDE_HELPERS_8` round was also **no regression** (`0/0.1/0.09 ms`, 25
matched pairs), so the user dropped it: scaling past six helpers does not pay.
`VICTORY_WIDE_HELPERS_10` is conditional on 8 winning and stays off.

- `VICTORY_WIDE_HELPERS` sets the off-phase active helper count (6 for the
  6-vs-8 round). It is an ordinary env setting, not a switch.
- `VICTORY_WIDE_THREADS_MAX` makes the pool large enough for a scaling A/B and
  stays fixed for the whole run. Its fork default is now six; `=3` restores the
  old ceiling.
- `VICTORY_WIDE_HELPERS_8` and `_10` remain A/B-able in the source tree but are
  off in frozen binary #2.
- The old refresh-scaling idea also raised `host::fine_job_factor()` to eight;
  that half is dropped with Cut 1a. Refresh spans stay one piece each; only who
  claims a piece changes.

`shadow::choose_wide_threads` clamps the requested count into
`wide_threads()..=VICTORY_WIDE_THREADS_MAX`, and `more_wide_tests` checks that
6, 8 and 10 claimers cover exactly the same numbers once each. These switches
are source-tree cuts for frozen binary #2 and are **not** in binary #1.

## Game A/B protocol

- Restart the PC before any test session that follows a long or overnight run.
  A machine-state slowdown was observed on 2026-11-27: the same cache, env and
  binaries loaded at ~1.2/s before a restart and at 69–207/s afterwards. Do not
  bisect code for this. If the library load rate falls below ~50/s, **stop the
  run and ask the user to restart the PC**; do not wait it out.
- Time zones: this PC reports local time as `FLE Standard Time` (UTC+02:00) and
  game-log lines are UTC (`...Z`). The user's visible clock is UTC+04:00, so
  add two hours to the PC-local `started=` line or four hours to a log's `Z`
  timestamp when comparing with what was seen on screen. Check with
  `Get-TimeZone` and `[DateTimeOffset]::UtcNow` before a session.
- warmed cache `victory-7900-clean-cache-1`; the harness now defaults to
  `victory-9070-cache-v3-fixed`, a copy with identical `known-pipelines.bin`,
  `known-shaders.bin` and `host-pipelines.bin`. If the manual driver-cache warm
  run does not restore time-to-gameplay, run the next baseline with
  `-Cache 'C:\mygame\victory-work\victory-7900-clean-cache-1'` before judging any
  cut.
- `VICTORY_LATE_WAIT=3`, fixed in `tools/harness-env.ps1`: stage 3 is what
  `copy-stages-5` and the previous A/B protocol used. Do not override it for
  the warm run, baseline or any cut.
- `VICTORY_AB=20,VICTORY_TEX_VIEW_CACHE`
- passive screen/motion/memory monitor
- watcher stops at phase 7 or 29.5 GB private and refuses to kill during
  shader/pipeline creation (the earlier copy-stages-5 protocol only; canonical
  fixed-view runs below stop at phase 63 or 29.5 GB)
- no manual input during automated runs
- Fixed-view key schedule: world entry (`2/5/8/11/20/75/78:Enter`) plus paired
  `F` taps every 15 s from 93 s (`93:F,93.6:F,108:F,...`). `F` is the stand-in
  pad's left-stick button; the second tap returns stance, and the pair resets
  the title's idle timer without moving the camera or player. Screenshots at
  25 s intervals after 120 s changed only 1.6–7.8% of pixels, confined to two
  small grid cells (scene motion), not a camera-wide cut. There is one view
  transition around 95–120 s, so the single canonical scored window is phases
  12–63 inclusive (10 s phases, 120–630 s). Every fixed-view comparison —
  each single-switch A/B, the combined stack, and any rerun — uses these exact
  bounds; there are no per-run windows. Score every complete matched pair
  whose phases lie inside 12–63:
  - single-switch: consecutive off→on pairs (`12→13` through `62→63`, at most
    26 pairs);
  - combined: all-off (bits 0) → all-on (bits 7) pairs (`16→23` through
    `56→63`, at most 6 pairs).
- Exclusions: phases with fewer than 3000 draws, incomplete pairs, pairs with
  more than 3% draw deviation, and visual gaps over 5 luma or 5 non-black
  points measured over the scored paired phases. If the `29.5 GB` private-memory
  stopper (or phase 63) ends a run early, score every complete pair inside
  `12–(last complete phase)` and report the number of pairs; do not extend or
  shift the window. Fewer than 4 scored pairs is `provisional`, not a decisive
  label. Earlier two-pair or 10%-tolerance runs remain provisional only.

Canonical fixed-view results on frozen binary #1: Cut 3
`VICTORY_HEAP_SYNC_SAFE` is a clean win (`-1.42/-1.22/-0.48 ms`, 6 pairs in the
earlier user-confirmed 12-23 rerun); 1b `-0.38/-0.35/-0.32 ms` over 24 pairs and
Cut 2 `0.17/0.12/-0.25 ms` over 25 pairs are both no regression. The combined
stack (1b + Cut 3 + Cut 2) is a clean win over six pairs: `48.08` to `45.47 ms`,
saving `2.61 ms/frame`, mean/median/p90 `-2.62/-2.63/-0.65 ms`, draws matched
`y` (`0.6%`), visual gaps `1.9` luma and `0` non-black points. The all-on
`45.47 ms` remains `0.27 ms` above the `45.2 ms` reference, so this is not yet a
verified 30 fps result. The user has now deferred visuals: the goal is
playability — stutters and baseline FPS. The combined stack is frozen as binary
#2 with 1b, Cut 2 and Cut 3 on by default; 1a, Helper 8 and RUSH stay off.

### Known visual issues (user report, 2026-11-27)

The user reports triangling/shimmer/popping on trees and transparent objects,
vegetation sometimes neon green, **some trees with red leaves**, fences,
transparent-object shadows, broken puddles/swamps, and no RT. All of these,
including the tree colours, are present in the stable branch too. They are
known issues and are deferred; visuals do not block the playability benchmark.
The tree colours were previously missing from the known-issues list and are now
recorded here and in `EXPERIMENT_LOG.md`.

The user's drive reports up to `~24 fps` on bridges/open water and below `20 fps`
when approaching land masses or areas with more cars/NPCs/objects. That route is
now the canonical playability benchmark: future cuts are compared over whole-run
distributions (mean, p90, p99, stutter count) alongside the fixed-view A/B.

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

Cuts 1a, 1b and 3 are implemented off by default in the frozen binary and are
being re-tested in that order, followed by Cut 2. The heap-wait follow-up
`VICTORY_HEAP_SYNC_RUSH` and the helper-count switches `VICTORY_WIDE_HELPERS_8`
and `VICTORY_WIDE_HELPERS_10` are written in the source tree but are not in that
binary; none is built or run until the frozen A/B sequence has landed.
Nothing is promoted to a default without a clean run and the user's visual
check.

Parallel filtering of live descriptor/title state is parked; it would change
which bytes upload.

## Local data safety

The working tree and warmed cache live under `C:\mygame\victory-work`, outside
Temp, so Windows Storage Sense cannot clear the warmed version-3 cache. The
paths in this file and in `tools/README.md` point there. Historical play logs
remain under `AppData\Local\Temp\opencode` and are not needed to rebuild.

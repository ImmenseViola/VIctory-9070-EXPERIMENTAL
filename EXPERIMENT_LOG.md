# Experiment log

Chronological record of the work that led to this fork. This is a research
log, not a changelog for a release. The tuned main tree keeps its own
`PERF_GOAL.md`; only the decisions relevant to this fork are mirrored here.

## 2026-11-26

### Diagnosis before the fork

- `manual-play1`, user-controlled: fast driving reported 9–12 fps;
  respawn near water 27–29 fps. Dense sampler showed 12.5–14.5 fps / 69–80 ms
  at 4.9–8.9k draws in driving views and 26.7 fps / 37.6 ms at 2.4k draws by
  water. Private memory climbed 11.7 → 29.9 GB in about three minutes.
- `view-delta analysis`: the 27 fps up/down view already had ~29.0 GB private,
  while slower dense views had similar or lower private. The delta followed
  draws/copies (2.4k / 33 MB vs 6–10k / 58–80 MB), not memory pressure.
  Card was ~55–61% busy with 14–23 ms/frame idle while the submitting thread
  worked, and 0.0 ms waiting on the card. Verdict: host-bound GPU starvation.
- Read-only ranking of the inline texture pass put cached view/handle reads
  first, no-view early exit second, host/resource lookups third, queue
  batching fourth. Parallel filtering was rejected as behaviour-changing.

### Rejected in the tuned tree before the fork

| Experiment | Result |
|---|---|
| `VICTORY_WATCH_CAP` | No FPS or memory win (44.42 vs 44.47 ms); private still ~27.5 GB. Parked. |
| `VICTORY_BATCH_SLOTS` | Regression: 53.7 vs 47.7 ms dense, 42.6 vs 38.2 ms quiet. Rejected. |
| `VICTORY_PORT_JOURNAL` | Mixed; helped in two matched cycles, confounded in others. Not promoted. |

These remain outside this fork. This repository starts from the tuned tree
with those switches still present but off by default.

### Fork created

- Repo `ImmenseViola/VIctory-9070-EXPERIMENTAL`.
- Branch `experimental/texture-pass-aside`.
- `5d784e3` — snapshot of the current dirty tuned tree.
- `0d2ccb0` — `VICTORY_TEX_VIEW_CACHE` (read-side caching).
- `efcd784` — experiment documentation.
- `5eb8383` — first clean A/B verdict.
- Later commits enable the view cache by default in this fork and flesh out
  the docs/tools; see `git log`.

### `texview-ab1` — inconclusive

`VICTORY_AB=20,VICTORY_TEX_VIEW_CACHE`, 20 s phases, movement schedule, warm
cache, stop at phase 7 or 29.5 GB private.

- Only the early matched pair was comparable: 33.4 ms on vs 37.9 ms off at
  6–8 draws.
- Phases 4–7 were confounded by world entry and draw swings: 11.6k off vs
  5.0k on, then 5.1k off vs 10.0k on.
- Private 26.1 GB at stop; all frames visible/non-black.
- Verdict: suggests a win, not enough to promote.

### `texview-ab2` — clean win

Same switch and binary, but Enter-only after world entry and no movement or
camera keys, so phases 4–7 share one scene.

| Pair | Off | On | Draws |
|---|---|---|---|
| Mean | 70.9 ms → 63.1 ms | −7.8 ms | 5,829 / 5,848 |
| Median | 53.0 → 52.0 | −1.0 ms | matched |
| p90 | 94.3 → 88.6 | −5.7 ms | matched |
| Mean | 64.3 ms → 59.8 ms | −4.5 ms | 5,835 / 5,829 |
| Median | 51.0 → 48.2 | −2.8 ms | matched |
| p90 | 89.6 → 82.2 | −7.4 ms | matched |

Frames stayed 96.7% non-black; private 25.8 GB at stop. The win is mostly in
mean (4.5–7.8 ms) and p90 (2.8–7.4 ms); medians moved only 1–3 ms, so the cache
mainly helps worst frames. Verdict: clean dense matched win. The switch was
then made the default **in this fork only**.

### `texview-visual1` — user visual check, series X

The user played the default-on binary for about ten minutes. Their report:

- could not tell by eye whether the frame rate was better than the main branch;
- vegetation still pops in and out;
- shallow water — puddles and shorelines — still renders black;
- FPS still drops while driving;
- car lights pop in and out / shimmer;
- eyes looked better, but they could not confirm that against the main branch.

No artifact was identified as new or caused by the cache. The run held 14–27
fps at 2.2–10.6k draws with no pipeline creation active at the stop. Private
memory reached 30.8 GB; the game was stopped cleanly and physical memory went
back to ~26 GB free. Verdict: visual check passed, but memory stability and
driving dips still block promotion to the tuned tree.

### `series-s-visual1` — series-S comparison

Same binary, cache on by default, no input script, passive screen/FPS/memory
monitor. The user found driving on quiet island roads much more responsive and
estimated the average in the 20s. Vegetation was confirmed to fade in with
distance and out farther away, i.e. distance-based LOD/streaming rather than a
new artifact from the cache.

Dense log (89 samples, 2k+ draws): 51.6 ms mean / 48.9 ms median, 20.3 fps
mean. Preparing took 39.3 ms (copies 15.2 ms at 50.9 MB/frame, textures 1.5 ms);
copying back took 10.5 ms at 9.1 MB/frame; the GPU reported only 0.27 ms of
wait. Mean 5.7k draws. Private memory reached 29.7 GB at the stop, with no
shader/pipeline work active. The frame is still host-bound: to reach 30 fps,
roughly 18 ms of the dense mean has to go.

### Copy composition — what the 51 MB/frame actually is

The `copystat` "largest ranges" lines count whole refresh spans, not bytes
moved: the top ten spans add up to ~500 MB/frame while the bus-traffic counter
reports only ~13 MB up and ~13 MB fetched in about 50 copies. `shadow::update`
copies only changed pieces via `watch::writes`, so the large spans are checked,
not sent. The host log's 15.2 ms / 50.9 MB "copies" includes the whole refresh
path, of which bus traffic is a smaller part. Traffic MB is per presented frame,
but its “different pieces” count is distinct 64 KiB pieces over the whole ~5 s
window (`traffic.rs:24-44`), not a per-frame piece count.

Busy title buffers over the bus (peak / average MB up per frame, pieces):

| Buffer (title address + length) | Size | Up | Fetched | What it is |
|---|---|---|---|---|
| `0xac6160000+0x3200000` | 50 MB (mapped) | 9.6 / 7.0 MB, ~160 pieces | 3.3 MB | large title buffer, host copy on card |
| `0xaf5b70000+0x1800000` | 24 MB (mapped) | 5.4 / 2.5 MB, ~118 pieces | 0.3 MB | large title buffer, host copy on card |
| `0xaee5f0000+0x1800000` | 24 MB (mapped) | 2.4 / 1.7 MB, ~45 pieces | ~0 | large title buffer, host copy on card |
| `0xaec460000+0x5a42d2` | 5.7 MB (private) | 2.3 / 1.9 MB, ~64 pieces | ~0 | title buffer, host copy on card |
| `0x962440000+0x2d00000` | 45 MB (private) | ~0 / 0.01 MB | 8.1 MB, ~720 pieces | fetch-heavy, almost no upload |
| `0xaf4e70000+0xc00000` | 12 MB (mapped) | 0.7 / 0.4 MB | 5.3 MB, ~38 pieces | mixed |

`shadow.rs:5270-5297` names these `title buffer <address>` and logs the large
ones as `large buffer copied to the host`; `host::traffic` is the source of the
bus numbers. Their writers are the title's CPU (page-fault/guard write
tracking) and shader UAV writes (`shadow.rs` pending ranges), not our texture
uploads. The logs do not name a higher-level owner such as "constants" or
"skinning"; that mapping still has to be established before a port.

This is why the next big win is likely another renderer port that stops a
whole category of these copies (as ports 5 and 6 did), not shaving work off
the remaining 50 calls.

### `VICTORY_HEAP_SYNC_EARLY` A/B, first attempt

- `heapsync-ab1` was manually assisted: the user pressed Enter while the game
  was loading. It is diagnostic only, not a verdict. Phases 0–5 were idle
  (4–11 draws); the stopper ended it at phase 11 because phase 11 had 11,323
  draws against 6,299 in the preceding off phase. Passive monitor saw visible
  gameplay (mean luma 88.7→101.6, non-black 97.0→87.5%, 19.9→22.8 GB private),
  but the route/matched-draw requirement was not met.

- `heapsync-ab2` had no manual input and stopped at phase 7 with phases 4–7
  above 5.4k draws, but it used the movement schedule that confounded
  `texview-ab1`, not that run's Enter-only-after-world-entry schedule. The
  passive monitor also saw different frames between sides (non-black 96.7% vs
  87.7%, luma 118 vs 102). Pair 1 had ~500 fewer draws on the on side
  (50.7/48.2 ms at 5,988/5,492 draws); only pair 2 is convincing
  (48.3/46.9 ms at 5,603/5,859 draws). Grouped numbers were 47.55 ms mean /
  45.9 ms median at 5,676 draws with early rounds on, against 49.5 ms / 48.0 ms
  at 5,796 draws with them off, and private stayed 22.1→23.0 GB. Verdict: **no
  regression, possible 1–2 ms, mechanism unconfirmed** — the end wait for heap
  records did not fall (9.9 ms off vs 10.8 ms on). Early rounds are already the
  default, so no action follows from this run. Future A/Bs use Enter-only after
  world entry, as in `texview-ab2`.

### Fetch-heavy `0x962440000` — read-touch evidence needed

The premise that ~8 MB is fetched in ~720 pieces per frame mixes two regimes.
`traffic.rs:24-44` divides bytes by presented frames but leaves the “different
pieces” count as a distinct-piece count for the whole ~5 s interval. The early
lines (`series-s-visual1-stderr.txt:5970`, `6201`) are upload-heavy: 0.30–0.34
MB/frame up in 720 distinct 64 KiB pieces, 0.00 MB fetched. Later fetch-heavy
lines (`:15378`, `:19951`, `:21221`) cover only 274, 133 and 137 distinct pieces
for 1.33, 7.56 and 8.05 MB/frame fetched. So the log proves neither that the
title CPU reads all of this 45 MiB span each frame nor that it reads only a
subset.

Fetch selection is not CPU-read telemetry. `relay_card_back`
(`host.rs:4864-4878`) builds flag sets from `!r.compared` and `torn::flagged`;
`flagged_pieces` (`host.rs:2710-2723`) picks pieces; then `host.rs:4884-4904`,
`4937-4940`, `4977-5010`, `5043-5069` fetch, count, copy back and merge them.
`copystat` “MB/frame” is host refresh/upload work, not title CPU reads
(`copystat.rs:1574-1579`), and can exceed the 45 MiB allocation because a range
can be refreshed more than once per frame.

The watcher has no general read-touch counter: the guard handler records WRITE
faults (`watch.rs:3822-3841`) and only retries read faults after remaps
(`watch.rs:3851-3857`, `3569-3595`). `VICTORY_PAGE_WRITES=0` counts only
completed raw DirectStorage/kernel reads into plain addresses
(`watch.rs:3338-3368`, `3391-3399`; `dstorage.rs:1611-1615`), a path normally
bypassed by `VICTORY_STREAM_NOTICE` (`xmem.rs:605-607`). A `PAGE_GUARD`
read-touch probe is possible in principle, but a fault handler cannot safely
perform the GPU fetch itself; it must stall the reader until the existing
ordered fetch path completes, or rely on an earlier prefetch with the same
ordering guarantees (`host.rs:2622-2636`, `4977-5069`).

**Verdict:** defer-fetch is *needs measurement*, not ready for code. Smallest
evidence step: log a per-frame 64 KiB read-touch bitmap for exactly
`[0x962440000, 0x962744000)` beside the `FETCHED` piece set, with fetch
behaviour unchanged. If the touch set is consistently near all 720 pieces,
the idea is dead; if it is small and stable, test a first-touch design that
preserves the current completion ordering.

### Refresh spans — written pieces alone cannot drive them

The dense line `refreshes 9.7 in 31 flushes of 7959, 6950 of them known to copy
nothing, 7948 on several threads` (`series-s-visual1-stderr.txt:54042`) is a
dispatch-policy result, not missing knowledge. `FLUSHES[1]` is spans,
`FLUSHES[2]` known-nothing spans, `FLUSHES[3]` spans handed to `wide_each`
(`host.rs:7761-7764`, `7797-7813`). Only 11 were removed by the submitting
thread; about 6,939 became known-nothing inside the worker. With
`VICTORY_LIGHT_REFRESH` and port 6 on, `refresh_spans` sets `many` almost
always (`host.rs:8507-8510`), `flush_all` skips its prefilter too
(`host.rs:8667-8679`), and the predicate is repeated per worker
(`host.rs:8533-8536`, `8707-8710`). `wide_each` only schedules indices
(`shadow.rs:1585-1607`).

`Shadow::nothing_new` (`shadow.rs:3997-4022`) is the real decision: in-place or
empty range, watched state not `NOT_WATCHED`, no overlapping pending shader
write, and `watch::nothing_new` coverage by clean guarded bits or an asking
hold with no newer note (`watch.rs:1425-1442`). Written pieces are real but
page-oriented: `GetWriteWatch` parts folded to 64 KiB bits (`watch.rs:40-43`,
`709-768`), monotonic timestamps (`81-120`, `149-164`), guard `PUBLISHED` set
after an ask and cleared when the block becomes writable or remaps
(`1882-1895`, `2193-2201`), our writes noted while an ask stands (`1236-1260`;
`host.rs:7598`, `host/place.rs:96`, `memory.rs:628/649`), and copy-back notes
made only after the bytes have landed (`land.rs:614`, `watch.rs:2616-2631`,
`2644-2647`, `2651-2700`).

That is not complete enough by itself. `ask_once` only gathers refresh ranges
on shadows that asked ahead (`host.rs:5823-5836`; `shadow.rs:3125-3128`);
unwatched and guarded-light copies are not asked. `ask_ahead_held` drops
published/refused ranges and ranges under two pieces (`watch.rs:789-799`), and
`ask_rest` skips them (`1127-1135`). Kernel ask failures can leave no hold and
mark the copy `NOT_WATCHED` (`shadow.rs:4034-4058`). `copied` is stamped only
for whole 64 KiB pages (`shadow.rs:4125-4151`), `ranged` keeps only the
last/longest fully taken range (`4174-4180`), so partial ends stay stale.
Pending shader writes are invisible to the kernel watch and force copies of
the gaps (`shadow.rs:3231-3233`, `3966-3992`). `ask_once_end` clears the hold
and `Step::Run` ends it mid-submission (`watch.rs:1219-1230`,
`host.rs:7656-7660`); `wrote` is skipped without a standing ask
(`watch.rs:1239-1246`), title writes during preparation are deferred
(`1076-1081`), and `VICTORY_WATCH_CAP` can drop notes after the dirty bit is
reset (`57-75`, `1019-1046`). The safe unit is the whole conjunction: asking or
publication coverage, watched state, no pending shader write, complete
`copied`/`ranged` coverage, and no newer note.

`run_deferred`/`Batch` must preserve every refresh's byte set and submission
position. `Step::Copy` flushes pending refreshes before the title write
(`host.rs:7588-7589`; `title_written` at `8399-8403`) and then notes our own
write (`7596-7598`). `Step::GpuWrite` flushes that copy's pending refresh and
then declares pending shader writes (`7668-7683`; `shadow.rs:3250-3270`).
Copy-back notes land only after the bytes are in. Therefore a cached skip must
be invalidated at `wrote`, `ask_once_end`, `title_written`, `writing`, landing
notes, and remap/open events; the current
`refresh_front`→`refresh_ahead`→`run_deferred`→`fill/flush`→`ask_once_end`
order (`host.rs:5840-5898`) is the ordering contract. Extra bytes can overwrite
newer title/shader writes; missing bytes leave the card copy stale.

**Verdict:** no optimisation code yet. The write-up first established the
byte/ordering contract; stage timing was added next as described below. A
sampled set of skipped spans can still be checked with the `refresh_check`
read-only pattern (`shadow.rs:4061-4115`), followed by A/B with
`VICTORY_REFRESH_CHECK=1` and `VICTORY_UPCOPY_CHECK=1`, plus `WATCH_CAP`,
`PAGE_PARTS=0` and `PORT_GUARD_PLAN` stress cases. Moving the predicate back
onto the submitting thread would move the 9.7 ms, not remove it
(`watch.rs:1563-1571`).

### Stage instrumentation, before any optimisation

`VICTORY_COPY_STAGES=1` in a diagnostics build now prints a second line beside
the frame line. It mirrors every existing `PREPARING[0]` addition and
subtraction, so `batch recording + refresh flushes + serial prefilters +
deferred fills + ask_ahead + unattributed` equals the frame line's "copies".
`refresh_check` and the per-span `nothing_new` checks are shown as nested
"within those" times, not added twice. Span gathering/walking and the
submission's copy segment are shown as outside "copies" because the existing
frame line never counted them there. Per-span timing is gated because there
are thousands of `nothing_new` calls a frame; without the gate only whole
blocks are timed.

`copying back` is split in the relay landing only: fence wait, fetch
recording/sending, and a residual for finding pieces, scanning beside the
fetch, merging and range notes. The three parts add up to `COPY_BACK[0]` for
every landing. Both breakdown lines are swapped immediately after their frame
line's counter, so the parts and the total come from the same report interval;
small negative residuals can still occur when a worker adds after the total's
swap, but window averages close. There is no behaviour change: no ordering,
bytes, waits or switch defaults move.

#### Measured breakdown (`copy-stages-2`)

The first attempt (`copy-stages-1`) was discarded: the launcher still used a
stale `target-exp\diag` binary, so no stage lines were printed. The launcher
default now points at `target\diag`, and the Enter-only schedule includes the
20 s world-entry Enter again.

The representative window is 22:31:20–22:35:30 UTC after automatic world
entry: 110 stage samples and 47 frame samples with at least 3000 draws and at
most 100 ms/frame. The passive monitor showed visible gameplay throughout
(luma 89.5–116.1, non-black 87.8–97%, private 22.7→25.3 GB). In that window
the frame line averaged 54.3 ms/frame, 18.6 fps, 13.38 ms "copies", 10.23 ms
"copying back", and 7200 draws/frame.

`copies` averaged 13.47 ms over the stage samples; the six printed inside
stages summed to 13.469 ms, so the mirror closes to round-off:

| Stage | Mean ms/frame | Share of copies |
|---|---:|---:|
| refresh flushes | 10.46 | 77.6% |
| batch recording | 2.18 | 16.2% |
| ask_ahead | 0.35 | 2.6% |
| deferred fills | 0.24 | 1.7% |
| unattributed residual | 0.24 | 1.8% |
| serial prefilters | 0.00 | 0.0% |

Within those, finding spans that copy nothing took 6.86 ms/frame: front-flush
workers 5.22 ms, all-flush workers 1.57 ms, before-shader-writes 0.07 ms, and
the submitting thread's serial prefilter about 0.00 ms. `VICTORY_REFRESH_CHECK`
was off, so its timed stage was 0.00 ms. Outside the frame line's "copies",
span gathering/walking took 2.17 ms/frame and the submission's copy segment
18.26 ms/frame; neither is added into "copies".

`copying back` averaged 10.66 ms over 241 report samples (the frame line in
the same window averaged 10.23 ms):

| Part | Mean ms/frame | Share |
|---|---:|---:|
| finding pieces, scanning beside the fetch, merging and ranges | 8.48 | 79.6% |
| waiting for a fetch's fence | 1.27 | 11.9% |
| recording and sending the fetch copy | 0.90 | 8.5% |

So the largest targets are inside refresh flushes (especially the 6.86 ms of
`nothing_new` checks on parallel workers) and the 8.48 ms copy-back residual,
not the 2.18 ms of batch recording, the 1.5 ms texture pass, or the 1.27 ms
fence wait. No optimisation has been chosen or written from this breakdown.

#### Whole-frame critical path (`copy-stages-4` and `copy-stages-5`)

The follow-up rounds added a submitting-thread wall split, relay waits, a
refresh-flush wall split, and `find_pieces` byte/pending coverage, all behind
`VICTORY_COPY_STAGES=1`. `copy-stages-5` used the warmed version-3 cache,
series S, upscaler 6, `VICTORY_CARD_BUFFERS_MIN_MB=1`, `VICTORY_LATE_WAIT=3`,
Enter-only after world entry, and no manual input. The passive monitor saw
visible gameplay (`Americas`, luma 88.8–121.7, non-black 86.5–96.9%,
private 22.32–23.33 GB, 5,352 and 9,039 draws at the two samples). The
watcher stopped it after 210 stage lines with no shader/pipeline work active.
The representative window 23:25:40–23:27:30 UTC has 96 critical, flush and
`find_pieces` samples plus 20 frame lines with at least 3,000 draws:

| Submitting thread | Mean ms/frame | Share of frame |
|---|---:|---:|
| whole frame | 45.22 | 100% |
| in submissions | 38.36 | 84.8% |
| title work/elsewhere | 6.50 | 14.4% |
| waiting outside submissions for the relay | 0.35 | 0.8% |

The submission part splits as: lists' steps 18.03, heap waits 8.65, asking
4.17, snapshots 2.16, card copies 1.98, bytes under flights 1.38, sending
0.95, card steps 0.55, sweep/gather 0.09, flight waits 0.39 (p90 1.21, max
4.29) and lock 0.01 ms. Nested in those segments, not additive: refresh
11.94, copies/fills 2.31 (overlapping the refresh timer), and span walking
0.39 ms. `copy-stages-4` independently measured 47.34 ms frame, 40.41 ms in
submissions, 19.75 ms lists, 13.43 ms refresh and 8.95 ms heap waits over 88
samples, so the split is repeatable rather than one window's skew.

Relay waits on the submitting thread are effectively zero: 0.00 ms inside
submissions and 0.35 ms outside in the corrected round (0.001 present, 0.352
read; every other reason 0.00). Pipeline waits were 0.00 ms. The frame line's
10.78 ms "copying back" is real CPU work but is not on the submitting
thread's wait path, so cutting it cannot directly shorten the 45 ms critical
path; it could only matter indirectly through CPU/memory contention.

Refresh flushes: the stage timer is 11.08 ms, and the parallel part's 11.26 ms
wall is 0.135 ms dispatch/queueing + 9.89 ms work on the submitting thread +
1.23 ms join/wait. The workers' summed CPU is 33.80 ms across 104.5 worker
jobs/frame (about 3.2 per flush over 32.6 flushes), 0.324 ms for the average
worker job and 0.326 ms for the slowest worker in each flush; actual
`Shadow::update` is 16.27 ms of that summed CPU. The caller's 9.89 ms, not
worker starvation or the 1.23 ms join, is the part to cut.

`find_pieces` checked 38.44 MB against snapshots, found 10.45 MB (27.2%)
different, and 38.44 MB — effectively all of the declared ranges — was
covered by pending UAV writes. A pending-range-only or pending-skip copy-back
therefore has almost no headroom and cannot discard the bytes that do differ.

Re-ranking after these measurements:

1. **Candidate A — per-shadow interval index plus per-flush span union** stays
   first. It attacks the 11.94 ms nested refresh and its 9.89 ms caller wall.
   Still an unproven 0.5–1.5 ms estimate; no code has been written.
2. **New: heap-wait attribution** is second, as a diagnostic before any cut.
   The 8.65 ms `begin_sync_heaps` wait is the second-largest submission
   segment and is directly on the critical path, but its mechanism is not
   known yet.
3. **Candidate B — incremental declared-range joining/ordering** is off the
   table for the direct 30 fps path. The submitting thread does not wait on
   the relay or landing; a copy-back cut only helps if it also relieves CPU
   contention, which this round did not establish.
4. **Pending-range-only copy-back** is also off the table: pending coverage is
   38.44/38.44 MB, with 27.2% of those bytes genuinely changed.

No optimisation or switch default changed in these rounds.

## Open work

- Find a multi-millisecond CPU cut on the submitting thread. Its 45 ms frame
  is 38 ms in submissions; within that, lists' steps 18 ms (refresh 11.94 ms
  nested, caller wall 9.89 ms) and heap waits 8.65 ms dominate. Copy-back's
  10.78 ms is real CPU work but the submitter does not wait for it, so it is
  not the direct critical path. The texture pass is only ~1.5 ms, so sub-ms
  texture cuts cannot reach 30 fps. Bus-traffic composition is above, but the
  big buffers sit above 4 GiB, outside `port::place_for`'s low-4-GiB graphics
  region; placing them in title memory would reintroduce PCIe-bound shader
  reads. A byte/order-preserving change must target the measured stages, not
  the whole batch blindly.
- The texture no-view early-finish switch was dropped: restoring `host.mirror` removed its only substantial saving, so it was not worth an A/B.
- Parked sub-ms texture cuts are not part of the 30 fps path.
- `VICTORY_HEAP_SYNC_EARLY` A/B is done: no regression, possible 1–2 ms,
  mechanism unconfirmed and confounded by movement/frame differences. Early
  rounds are already the default; no action. Copy stage timing is also done;
  the numbers above direct the next optimisation.
- Full heap-texture aside only after the ahead-job refactor is safe.
- Memory wall (~30 GB private) and dense driving dips remain separate
  stability problems; no switch here claims to solve them. The promotion test
  is "no worse than baseline on memory", not a fix of this wall.
- Vegetation distance fade is suspected by the user to be a RAM/streaming
  ceiling rather than ordinary LOD. Parked by request until the multi-ms CPU
  work is done; no change has been made for it.

## Cut 1a and 1b implemented, awaiting game A/B (2026-11-27)

Both cuts are in the experimental tree, off by default, and A/B-able.

- **Cut 1a — `VICTORY_REFRESH_FINE_JOBS`**: `host::fine_spans` splits each
  refresh span into at most four jobs, no piece under `256 KiB`, in the three
  wide refresh dispatch sites (`refresh_spans`, `refresh_ahead`, `flush_all`).
  Byte union, span order, `ahead` marking, ask windows, and title-write
  boundaries are untouched. Unit test:
  `host.rs::tests::fine_refresh_jobs_have_the_same_bytes_in_the_same_order`.
- **Cut 1b — `VICTORY_WIDE_REFRESH_MORE`**: `shadow::active_wide_threads` can
  wake more helpers kept by a fixed `VICTORY_WIDE_THREADS_MAX` ceiling. Off
  helpers wait without spinning; raising the count wakes them before dispatch.
  The atomic index counter still gives every piece to exactly one claimer.
  Unit test: `shadow.rs::more_wide_tests::more_helpers_claim_the_same_work`.

Verification before push: `cargo check --workspace --all-features --locked`,
`cargo test --workspace --all-features --locked`, `cargo clippy --workspace
--all-targets --all-features --locked -- -D warnings`, `cargo build --locked
--profile diag -p victory --features diagnostics`, and `git diff --check` all
passed. No game result yet; no default changed.

Push note: the first push of `7c78e2a` mistakenly used the `origin` remote,
which is the tuned `VIctory-9070` repository, and created a branch there as
well as moving its `main`. It was corrected immediately: the stray branch was
deleted and tuned `main` was force-restored to `5194620`; `git ls-remote` now
shows tuned `main` at `5194620` and no stray branch. The commit was then pushed
to the `experimental` remote, whose `main` and `experimental/texture-pass-aside`
both point at `7c78e2a`. Future pushes must name the `experimental` remote
explicitly.

## Cut 1a game A/B started (2026-11-27)

`cut1a-fine-1` launched with the warmed version-3 cache, `series-s`, upscaler
`6`, Enter-only schedule, `VICTORY_AB=20,VICTORY_REFRESH_FINE_JOBS`, and
`VICTORY_COPY_STAGES=1` for stage attribution. First monitor and stopper were
started with a 120 s harness timeout and were terminated by that timeout while
shader translation was still active; the game itself stayed alive. They were
restarted with a 900 s timeout, a 120 s monitor warmup, and cycle ends
`7,15,23,31` so that a clean post-startup cycle can be used. No result or
label yet; the game is still translating shaders and showing 1 draw/frame.

Cut 1c was investigated read-only and is parked: there are no adjacent
production refresh-flush sites with no title write, `flush_one`, `Step::Run`,
non-free `Step::Placed`, texture-due change, or `ask_once_end` between them.
The only adjacent flush calls are in the test helper
`refresh_tests::submission`, so a game-facing switch would be dead code. No
Cut 1c switch or test was added; the order moves to Cut 2.

The `cut1a-fine-1` monitor finished twelve samples, all at 1 draw/frame, mean
luma `7.9`, non-black `5.1–5.2%`, private `6.76–7.11 GB`: the game was still
at the menu/loading screen because shader translation continued past the
scripted Enter presses. Manual Enter attempts while translation was active
did not change the draw count. The first replacement stopper was stopped
before its deadline; `tools/stop-after-clean-ab.ps1` was then hardened so a
deadline reached while shader translation is active extends to a hard
deadline and never kills a busy game. A new `tools/enter-when-quiet.ps1` helper
waits for a quiet translation window and sends Enter then; both are running
for this same A/B attempt. No result or label yet.

## Cut 1a game A/B result — crash / confounded, switch stays off (2026-11-27)

The quiet-window Enter helper fired at `02:43:46+02:00` and sent three Enters,
but the run never reached active gameplay: every parsed phase reported
`1 draw/frame`, the title stayed on the menu/loading presentation, and shader
translation continued through most of the run. At `00:47:03Z` the title logged
a first-chance `0xc0000005` write to address 0 in
`victory-image-b99f876b74d4a77f.dll+0x2215c35`; at `00:47:51Z` it became an
unhandled exception with the same stack, followed by Breakpad crash context
`t:\victory-20261127-024825-4648.crash.log` and minidump
`T:\caa50b27-8899-4d03-93e7-f0266d058e6a.dmp`. The process exited after phase
91; the stopper recorded `STOP_REASON=exited` and did not kill it.

Phases 80–91 were parsed for the final attempt (full output saved as
`C:\mygame\victory-work\cut1a-fine-1-full-report.txt`):

- off: 2143 frames across 6 phases, mean of means `70.77 ms`, mean of medians
  `33.32 ms`, max p90 `33.8 ms`, `1` draw/frame; on (`VICTORY_REFRESH_FINE_JOBS`):
  2631 frames across 6 phases, mean of means `6267.95 ms`, mean of medians
  `6256.9 ms`, max p90 `37374.9 ms`, `1` draw/frame.
- matched off→on pairs: `80→81` `+0.0 ms`, `82→83` `+0.0 ms`, `84→85`
  `+1.6 ms`, `86→87` `+37326.8 ms` (on side 1 frame, 0 draws), `88→89`
  `-69.3 ms`, `90→91` `-76.0 ms`; medians were `0`, `0`, `0`, `+37341.6`,
  `-0.1`, `0`; p90 deltas `0`, `0`, `0`, `+37341.3`, `-0.1`, `-0.2`; draw
  ratios `1` except `0.833` for the crash pair.
- visual/memory: the monitor had finished its 12 samples before the later
  phases, so all samples are on the off side: mean luma `7.9`, non-black
  `5.1–5.2%`, private `6.76–7.11 GB`, changed `0–0.1%`. There is no on-side
  luma/non-black sample, so the visual comparison is unavailable; the run was
  not a gameplay cycle.
- stages in parsed phases: refresh recording `0.05–0.51 ms`, refresh worker
  stage `0.05–0.51 ms` with `0.00 ms` summed worker CPU and 0 worker jobs,
  critical-path lists `0.1–0.7 ms` in `13–91` flushes, sending `0.4–3.3 ms`,
  ask/gather/sweep near zero, heap waits `0.1–2.68 ms`; the last diagnostic
  frames had `33.1–33.2 ms` in title work/elsewhere. These are not gameplay
  numbers.

Final label: **confounded** from the full-report rule (mean delta on-off
`6197.18 ms`, p90 max delta `37341.1 ms`, draw ratio `0.833`), with an
additional title crash during phase 87. Per the run rule, there is no retry:
`VICTORY_REFRESH_FINE_JOBS` remains off by default and Cut 1a is not a win.
The game is fully closed.

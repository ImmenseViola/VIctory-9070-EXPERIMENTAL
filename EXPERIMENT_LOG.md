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

- `heapsync-ab2` was clean: no manual input, warmed cache, series-S, and the
  stopper ended at phase 7 with phases 4–7 all above 5.4k draws. Passive monitor
  saw active gameplay (mean luma 118.2 and 101.6, non-black 96.7% and 87.7%,
  private 22.1→23.0 GB). Phase 4/5 were 50.7/48.2 ms at 5,988/5,492 draws;
  phase 6/7 were 48.3/46.9 ms at 5,603/5,859 draws. Grouped, the current early
  default (`bits=1`, early rounds on) was 47.55 ms mean / 45.9 ms median at
  5,676 draws, against 49.5 ms / 48.0 ms at 5,796 draws with early rounds off.
  That is a ~2 ms win, but the measured end wait for heap records did not fall
  (9.9 ms off vs 10.8 ms on), so the mechanism is not confirmed. No default is
  changed by this run; the early rounds are already the current default.

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

**Verdict:** no code yet. First add reason counters to `Shadow::nothing_new`,
tag each `FLUSHES[2]` increment with its site, and verify a sampled set of
skipped spans with the `refresh_check` read-only pattern
(`shadow.rs:4061-4115`). Then A/B with `VICTORY_REFRESH_CHECK=1` and
`VICTORY_UPCOPY_CHECK=1`, plus `WATCH_CAP`, `PAGE_PARTS=0` and
`PORT_GUARD_PLAN` stress cases. Moving the predicate back onto the submitting
thread would move the 9.7 ms, not remove it (`watch.rs:1563-1571`).

## Open work

- Find a multi-millisecond CPU cut: copy recording (15.2 ms) and copy-back
  (10.5 ms) are the two largest measured pieces; the texture pass is only
  1.5 ms now. Bus-traffic composition is above, but the big buffers sit above
  4 GiB, outside `port::place_for`'s low-4-GiB graphics region; placing them in
  title memory would reintroduce PCIe-bound shader reads. The next step is a
  byte/order-preserving change to copy recording (`host.rs::run_deferred`,
  `host.rs::Batch`), where ~6900 of ~7900 refresh spans per frame are known to
  copy nothing. Sub-ms texture cuts cannot reach 30 fps.
- The texture no-view early-finish switch was dropped: restoring `host.mirror` removed its only substantial saving, so it was not worth an A/B.
- Parked sub-ms texture cuts are not part of the 30 fps path.
- `VICTORY_HEAP_SYNC_EARLY` A/B is done: the current early default measured
  ~2 ms better in the clean dense cycle, but its end wait did not fall, so it
  is not a proven mechanism. No default change; copy recording is next.
- Full heap-texture aside only after the ahead-job refactor is safe.
- Memory wall (~30 GB private) and dense driving dips remain separate
  stability problems; no switch here claims to solve them. The promotion test
  is "no worse than baseline on memory", not a fix of this wall.
- Vegetation distance fade is suspected by the user to be a RAM/streaming
  ceiling rather than ordinary LOD. Parked by request until the multi-ms CPU
  work is done; no change has been made for it.

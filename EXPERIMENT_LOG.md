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
- `3da9305` — `VICTORY_TEX_SKIP_NOVIEW`.
- `13ee0cc` — skip-noview documentation.
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

Frames stayed 96.7% non-black; private 25.8 GB at stop. Verdict: clean dense
matched win. The switch was then made the default **in this fork only**.

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

## Open work

- Find a multi-millisecond CPU cut: copy-back and copy recording are the two
  largest measured pieces after the texture view cache.
- Game A/B of `VICTORY_TEX_SKIP_NOVIEW`, alone and then combined with the
  view cache.
- `VICTORY_TEX_HOST_CACHE` and `VICTORY_TEX_QUEUE_BATCH` experiments.
- Full heap-texture aside only after the ahead-job refactor is safe.
- Memory wall (~30 GB private) and dense driving dips remain separate
  stability problems; no switch here claims to solve them.

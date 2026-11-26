# VIctory-9070 EXPERIMENTAL

Isolated home for risky texture-pass work. The tuned tree in
`VIctory-7900XTX` and its `main` branch are deliberately untouched.

- Repo: <https://github.com/ImmenseViola/VIctory-9070-EXPERIMENTAL>
- Branch: `experimental/texture-pass-aside`
- Baseline: current tuned tree, commit `5d784e3`
- Switch commit: `0d2ccb0`

## Goal

The distant view in the tuned build is host-bound, not VRAM-bandwidth-bound:
the card is only ~55–61% busy and sits idle while the submitting thread
prepares descriptor/refreshes/copies. The heap-texture pass is one of the
remaining inline costs (roughly 7–10 ms in dense views). The long-term idea
is to move that pass aside; the immediate experiment is to remove only work
that is provably read-side.

## `VICTORY_TEX_VIEW_CACHE`

Off by default. Enable for one run with:

```powershell
$env:VICTORY_TEX_VIEW_CACHE='1'
```

or compare in one run with:

```powershell
$env:VICTORY_AB='20,VICTORY_TEX_VIEW_CACHE'
```

A switch named in `VICTORY_AB` no longer follows its own environment value.

### What it changes

In `crates/victory-gpu/src/draw.rs`, `State::heap_textures` currently reads
the same descriptor many times for one due slot:

- `heap.handle(index)` up to ten times,
- `heap.handle(index).and_then(descriptor::view)` several times.

With the switch on, each due slot lazily caches:

- one `Option<u64>` handle, and
- one `Option<View>` raw descriptor view,

then reuses them for the rest of that slot. `host.mirror`, `texture_slot_*`,
`ahead::take/send`, `readable`, and every deferred step are still called at
the same points and in the same order. With the switch off the old reads are
performed exactly where they were before.

### Why it is experimental

The title can write a descriptor while the texture pass is running. The
cached raw view can therefore be slightly older than a fresh read later in
the same slot. That is the only semantic change; it is deliberately kept out
of the tuned tree until game A/B and visual checks say otherwise.

### What it does not do

- It does not move D3D recording off the submitting thread.
- It does not reorder uploads, barriers, refreshes, or host writes.
- It does not change texture selection, budgets, or slot lifetimes.

A full `aside::begin` offload of `heap_textures` is **not** safe: that
function records commands into the title's list and needs a much larger
ahead-job refactor. See `PERF_GOAL.md` in the parent temp folder for the
mapping.

## Validation

Build and tests:

```powershell
cd 'C:\Users\Admin\AppData\Local\Temp\opencode\VIctory-9070-EXPERIMENTAL'
$env:CARGO_TARGET_DIR='C:\Users\Admin\AppData\Local\Temp\opencode\VIctory-9070-EXPERIMENTAL\target-exp'
cargo test -p victory-gpu --features diagnostics
cargo build --locked --profile diag -p victory --features diagnostics
```

Last build: 434 unit tests + replay tests passed; binary at
`target-exp\diag\victory.exe`.

Game A/B protocol:

- warmed cache `victory-7900-clean-cache-1`,
- `VICTORY_LATE_WAIT=3`,
- `VICTORY_AB=20,VICTORY_TEX_VIEW_CACHE`,
- passive screen/motion/memory monitor,
- watcher stops at phase 7 or 29.5 GB private and refuses to kill during
  shader/pipeline creation,
- no manual input during the automated run.

### Results

| Run | Outcome |
|---|---|
| `texview-ab1` | Clean cycle, but world entry and camera/draw swings confounded phases 4–7. Only matched pair: 33.4 ms on vs 37.9 ms off at 6–8 draws. Suggests a win; not enough to promote. |
| `texview-ab2` | Clean matched dense pairs at ~5.83k draws. Phase 4 off 70.9 ms mean / 53.0 median / 94.3 p90 vs phase 5 on 63.1 / 52.0 / 88.6. Phase 6 off 64.3 / 51.0 / 89.6 vs phase 7 on 59.8 / 48.2 / 82.2. About 4.5–7.8 ms mean and 2.8–7.4 ms p90 better with the cache. Frames stayed 96.7% non-black; private 25.8 GB at stop. |

Promotion requires a clean dense matched A/B, stable memory, and a visual
check by the user. Nothing is promoted to the tuned tree until then.

## Next cuts, in order

1. `VICTORY_TEX_SKIP_NOVIEW` — after the room/residency gates, skip slots
   whose cached raw view can never produce a host texture. Expected
   0.1–0.5 ms; medium-low risk.
2. `VICTORY_TEX_HOST_CACHE` — avoid a repeated `GetDesc`/`hosted()` and a
   second `placed_texture` per candidate. Expected 0.2–1 ms; low-medium
   risk.
3. `VICTORY_TEX_QUEUE_BATCH` — coalesce host-slot mutex updates. Expected
   0.2–1.5 ms in backlog-heavy passes; medium risk because `room` checks
   must stay in the same places.

Parallel filtering of live descriptor/title state is deliberately parked;
it would change which bytes upload.

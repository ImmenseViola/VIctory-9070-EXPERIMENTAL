# VIctory for Radeon RX 9070 (RDNA4)

> ## ⚠️ EXPERIMENTAL FORK
> This is **not** the tuned main tree. It exists to carry risky performance
> experiments away from `ImmenseViola/VIctory-9070`. Experimental switches may
> be on by default here, may change behaviour, and may be reverted. Read
> [EXPERIMENT.md](EXPERIMENT.md) and [EXPERIMENT_LOG.md](EXPERIMENT_LOG.md)
> before using it. Nothing here is a release.

A tuned fork of [VIctory](https://github.com/Marvisak/VIctory): a compatibility
layer that runs an Xbox Series title natively on Windows from files the user
supplies. It starts from the tuned
[VIctory-7900XTX](https://github.com/avatarmanz/VIctory-7900XTX) tree and adds
the RDNA4 fixes needed to keep NPC skinning, avoid AMD driver faults, and show
frame data while playing.

**This repository contains no game files, code or assets.** You need your own
copy of the game. It is not affiliated with or endorsed by the game's developer
or publisher.

## The goal

**Stable double-digit FPS on an RX 9070 with ray tracing off, then as high a
frame rate and as low frame times as the PC allows.** The tuned 7900 XTX build
still targets 30 fps or more on that card. We prefer a smaller patch that is
warm on first launch to a larger one that stutters while compiling.

The way there is **porting, not emulating**: patch the title's renderer so it
behaves like a PC renderer, instead of copying the console's shared memory
every frame. Shaders are translated ahead of time into a versioned store that
survives rebuilds. Ray tracing stays optional and off by default. The picture
comes after the frame rate: foliage flicker, black glass, and texture pop-in
are still open.

## Where it stands (2026-11-26)

Everything below is inherited from the tuned tree. The only thing this fork
changes today is the texture-view cache described in
[EXPERIMENT.md](EXPERIMENT.md); the measured A/B result is in
[EXPERIMENT_LOG.md](EXPERIMENT_LOG.md). Nothing here has been promoted back to
`ImmenseViola/VIctory-9070`.

### RX 9070 / RDNA4 release check

Windows 11 build 26200, Ryzen 5 7500F, 32 GB RAM, RX 9070 (`0x7550`, 16,191 MiB
VRAM), driver 8.18.10.0514, Series S profile, ports 1/2/5/6, 1920x1080 output,
FSR upscaler 6, ray tracing off.

| | |
|---|---|
| NPC skinning | restored: ped flickering gone, NPCs render correctly |
| Indoor scene in play test | about 21 FPS |
| Boat scene in play test | 16-22 FPS in the user's mission run; the mission was completed successfully |
| Boat scene, clean guard-off rerun | 30 world samples, 17.61 FPS mean, 18.7 FPS median; no refused compute, no error or fault |
| Outdoor early game in the *experimental* build | 1-6 FPS with large stutters; likely wrong host-size offset, shader recompilation and/or asset streaming, not yet separated |
| Final release validation | 480-second run, fresh version-3 cache, overlay on: 18.27 FPS mean, 19.6 FPS median; no game or driver fault |
| Panel | top-left FPS, frame ms, longest frame, GPU busy, RAM, VRAM, system CPU and VIctory CPU |
| Translator cache | version 3; older caches must be regenerated |

The release check had 149 world-frame samples. The first two minutes were the
stutter: 0.1-6.9 FPS while 1,600+ pipelines were still being made and 54 ms a
frame was spent waiting for them. From minute 3 to minute 11 it held about
18-21 FPS (median 21.2 in several minutes); the last two minutes were about
15 FPS, matching the boat/late-scene report. GPU memory stayed around 11.7 GB
of a 14.2 GB budget. There were no `ERROR` lines, no device removal, and no
`0xc0000005`; the guard refused one pipeline from a bad list written before the
host-size fix. Later play showed that list was stale: it also named the fixed
skinning shader and refused hundreds of compute draws in busy scenes. The guard
now ignores lists that do not carry the current driver/translator fingerprint.
The launcher was stopped by the shell's 900-second timeout after its 470-second
screenshot; the game itself was still running normally.

The guard fix was then checked in a fresh game session after a clean warm:
2,138 pipelines made, 0 bad, and 3,951 shader-cache hits with 0 misses. The
boat scene held 17.61 FPS mean and 18.7 FPS median across 30 samples. There
were no `refused [compute]` drops, errors, or faults; the remaining
“without a host pipeline” drops were the intentionally disabled ray-tracing
structure builder. A 6,369-draw frame held 11.3 FPS where the stale-guard run
had similar scenes at about 5 FPS. The skinning shader `f16876929fa64f9f`,
eye shader `1512b6b81c4072ed`, and reflection shader `29be03ccaa4e353a` were
all translated, given host pipelines, and bound normally.

The earlier 300-second guard build also completed without a crash at 18.16 FPS
mean and 21.0 FPS median, but it still had skinning disabled, so it is only a
stability datapoint.

### RX 7900 XTX baseline (inherited tuned tree)

Windows 11, i9-12900K, 64 GB RAM, RX 7900 XTX 24 GB, ray tracing off.

| | |
|---|---|
| City street, Series S profile, renderer patches 1, 2, 5 and 6 on | about 45 ms a frame (about 22 fps), p95 47 ms |
| Same, patches 1, 2 and 5 | 47.3 ms (about 21 fps), p95 49 ms |
| Series X profile, patches 1+2 | about 53 ms (about 19 fps) |
| Same scene before the patches | 57-75 ms (13-17 fps) |
| Shaders the title uses that translate | all of them (25,790 of 25,985; the rest are unused geometry shaders) |
| Memory | about 30 GB of private memory, 10.5 GB of VRAM: **64 GB of RAM recommended** for the tuned XTX profile |

It started at 280 ms a frame in the same scenes three days earlier. What sets
the frame now is the one thread that submits the title's work to the card
(about 42 ms); the card itself needs about 36 ms.

Details and measurements: [docs/findings.md](docs/findings.md). The RDNA4
investigation, including the rejected approaches, is in
[docs/rdna4.md](docs/rdna4.md).

## RDNA4 fixes in this release

- **NPC skinning is back.** `CS_PedStandardSkinning_12_15f19d85_Wrapped` is no
  longer skipped. The driver fault was in
  `CSComputeSkinningTreeAnimVelocity_d2f99501_Wrapped`, not in the visible
  ped shader.
- **Buffer sizes come from the host, not a driver-fragile DXIL query.** The
  host writes a third table of view byte lengths beside the existing stride
  and address tables. A shader that names a buffer view through a descriptor
  table or the view heap reads that length with one `rawBufferLoad`. The
  offset is `VIEW_SIZES + slot * 4` bytes. Descriptors built from root
  arguments and all texture dimensions are unchanged.
- **Translator version 3** invalidates the experimental wrong-offset cache.
  Regenerate shaders and pipelines after updating.
- **Bad RDNA4 pipelines can be refused when asked.** With
  `VICTORY_SKIP_WARM_BAD=1`, runs refuse only the exact pipelines and shader
  hashes in `warm-bad.txt` / `warm-bad-shaders.txt` whose first word is the
  current driver/translator fingerprint. Older lists, and the broad
  `CS_RaytracingResolve_*` family rule, are ignored: they refused real gameplay
  compute work after the host-size fix. Nothing is skipped by default.
- **The shader registration lock is released before parsing a container.**
  This removes a hot lock around two scans and a copy; two threads can build
  the same container, and only the one inserted is counted.
- **The overlay shows CPU too.** `VICTORY_PANEL=1` now draws system CPU use,
  VIctory's own CPU use, and panel cost next to FPS, frame time, RAM and VRAM.

XCL's global wave64 split was deliberately not ported: it was a compile-hang
workaround and can be 1.3x to 5x slower. Rayon was not added; the target
already has a persistent `wide*` worker pool.

## Known problems

- Trees and grass still shimmer/flicker, including in the boat scene. One piece
  of vegetation rendered neon green in the playthrough. The skinning fix did
  not touch vegetation.
- Glass sometimes renders black. Sunglasses and eyes can look blueish, as if a
  reflection pass were wrong.
- In dialogue, face textures and beards moved but the model's lips did not in
  the stale-guard playthrough. The clean rerun binds the skinning shader
  normally; visual confirmation is still needed.
- Dark interiors can show artifacts around the character and dust in the air.
- The picture can look soft in Series S mode at 1080p with upscaler 6. Series X
  or a higher output sharpens it at a frame-rate cost.
- A busy-street gunfight fell to about 5 FPS while the stale warm-bad list
  refused hundreds of compute draws. The list is now ignored and a clean rerun
  held 11.3 FPS at 6,369 draws with zero refused compute work.
- Lighting can be too bright or too dark after walking indoors until the
  title has settled; rooms with little direct light are too dark without
  `-RayTracing`.
- Textures of what just came into view appear late while the title streams,
  especially from SATA storage.
- Early outdoor scenes can still stutter and fall to single digits while new
  shaders and pipelines are made. Warm both caches before measuring.
- With 32 GB of system RAM, long XCL-style sessions can lose speed late in a
  run; 64 GB is safer for long tests.
- Recording a frame in the world makes the title's own watchdog end it.

## How to run it

You need Windows 10/11 x64, a CPU with AVX2, a Direct3D 12 GPU with shader
model 6.6 and mesh shaders, Rust (the toolchain is pinned), the MSVC build
tools, and your own dump of the title.

```powershell
git clone https://github.com/ImmenseViola/VIctory-9070-EXPERIMENTAL.git
cd VIctory-9070-EXPERIMENTAL
copy victory.example.toml victory.toml      # then set your paths, outside this folder
cargo build --locked --profile diag -p victory --features diagnostics
scripts\play.ps1 -Exe <path of your copy's executable>
```

`scripts\play.ps1 -Safe` leaves out the newest, faster ways; try it first when
something is wrong. `-RayTracing` turns the title's ray-traced indirect light
on, but implies `VICTORY_BVH_BUILDER=1`, which is not part of the tested
release. Run the script from a normal window, not as administrator: the driver
then keeps its shader cache elsewhere. The tuned launchers also auto-focus the
window and press Enter through `VICTORY_KEYS`; keep that if you measure a run.

For an RX 9070, start from the tuned ports and add the RDNA4 switches:

```powershell
scripts\play.ps1 -Exe <your game.exe> -More @{
    VICTORY_PORT_CONSTANTS = '1'; VICTORY_PORT_DESCRIPTORS = '1'
    VICTORY_PORT_CBV = '1'; VICTORY_PORT_GUARD = '1'
    VICTORY_PANEL = '1'
    VICTORY_UPSCALER = '6'; VICTORY_OUTPUT = '1920x1080'
    VICTORY_RESIDENCY = '1'; VICTORY_ASYNC_SUBMIT = '1'
    VICTORY_LATE_WAIT = '1'
}
```

When invoking `victory run` directly, add `--console series-s` for the Series S
profile. On a hybrid-graphics PC, the runtime and offline pipeline checks
prefer a high-performance adapter with Shader Model 6.6. The runtime logs its
adapter name, PCI vendor and device IDs, and dedicated VRAM. Set
`VICTORY_D3D12_ADAPTER` to a zero-based DXGI index or part of the adapter's
name to select it explicitly.

Because the translator version moved to 3, warm the caches after a fresh
build (both can be stopped and go on later):

```powershell
target\diag\victory.exe translate <the shader archives> --warm all --jobs 12
target\diag\victory.exe warm --used --jobs 8
```

`VICTORY_CACHE_DIR` must point to the same cache for translation, warming, and
play. Do not reuse a version-2 cache.

Commands, debugging switches and upstream's own description:
[docs/README-fxceless.md](docs/README-fxceless.md). Every `VICTORY_...` switch
is described in a comment where it is read.

## Switches and safety

The tuned renderer patches are off by default as upstream exposes them:

| Switch | What it does |
|---|---|
| `VICTORY_PORT_CONSTANTS=1` | The title's 174 MB constants heap is read by the card where the title writes it: no uploads, no fills |
| `VICTORY_PORT_DESCRIPTORS=1` | The title's descriptor-table stores are byte-checked to report the slots they write, instead of scanning ~600,000 slots a frame |
| `VICTORY_PORT_CBV=1` | Translated shaders read constant buffers in place as raw bytes |
| `VICTORY_PORT_GUARD=1` | Write guards share a lock with refreshes and a claim per 64 KiB block; submission planning runs beside it |
| `VICTORY_SKIP_WARM_BAD=1` | Optional: refuse exact pipelines/shaders from a fresh bad list for this driver and translator; leave off otherwise |
| `VICTORY_PANEL=1` | Draw the top-left FPS/frame-time/GPU/CPU overlay |
| `--console series-s` | Series S profile: 1080p output, about 5 ms faster, a softer picture |
| `VICTORY_OUTPUT=1920x1080` | The title renders to that output size itself |
| `VICTORY_FRAME_INTERVAL_MS=16.667` | Lets the title go above 30 fps (menus and videos reach 60; the game's clock stays right) |

Other useful tuned switches are `VICTORY_ASYNC_SUBMIT=1`, `VICTORY_LATE_WAIT=1`,
`VICTORY_THIN=1`, `VICTORY_RELAY=1`/`2`, `VICTORY_UPSCALER=6`,
`VICTORY_RESIDENCY=1`, plus the heap (`VICTORY_HEAP_TEXTURES=0`) and card
(`VICTORY_CARD_STEPS=2`) settings, `VICTORY_PIPELINE_WAIT_SHARED`, `VICTORY_WIDE_REFRESH` and
`VICTORY_LIGHT_REFRESH` settings from [docs/findings.md](docs/findings.md).

**Do not use these for a release build** unless you are deliberately
experimenting: `VICTORY_SEND_CHANGED=1`, `VICTORY_BVH_BUILDER=1`,
`VICTORY_COPY_MODE=plain/none`, `VICTORY_PAGE_WRITES=1`,
`VICTORY_TEXTURE_FILL=0`, `VICTORY_UNWATCHED_FRAMES>1`, `VICTORY_SKIP_DIMS`,
`VICTORY_FIRSTLANE_BALLOT=1`, `VICTORY_FORCE_WAVE32_META=1`,
`VICTORY_RAW_LOAD_I32=1`, `VICTORY_SKIP_TYPED_STORE=1`, and
`VICTORY_SHADER_OVERRIDE`. They are diagnostic, unproven, or the opposite of
the tuned configuration. `VICTORY_SHADER_SAVE`, `VICTORY_EMIT_DUMP`, and
`VICTORY_SHADER_FRESH=1` only write or compare data and are safe when you have
the disk space.

## Experimental switches in this fork

These are **not** in the tuned tree. Defaults below are for
`experimental/texture-pass-aside`; both branches of this repo carry them, and
the tuned `ImmenseViola/VIctory-9070` tree carries neither.

| Switch | Default here | What it does | Status |
|---|---|---|---|
| `VICTORY_TEX_VIEW_CACHE` | **on** | Reads each texture slot's heap handle and raw view once, instead of on every look in that slot | Clean dense A/B win (4.5-7.8 ms mean, 2.8-7.4 ms p90); visual check found no new artifact, still blocked on memory stability |
| `VICTORY_TEX_SKIP_NOVIEW` | off | Early-finishes due slots whose view can never name a host texture, after mirroring them | Trace found stale-descriptor paths; mirror restored. Off and unmeasured |

To get the tuned behaviour, launch with `VICTORY_TEX_VIEW_CACHE=0`. For a
one-run comparison use `VICTORY_AB=20,VICTORY_TEX_VIEW_CACHE`; a switch named
in `VICTORY_AB` no longer reads its own environment value. The cache changes
only when a raw descriptor view is read; no upload, barrier, refresh, command
order, or texture lifetime moves. The risk is that the title can write a
descriptor while the pass runs, so a cached view can be slightly older than a
fresh read. That is why it is still an experiment.

Full protocol, results, and the next planned cuts:
[EXPERIMENT.md](EXPERIMENT.md) and [EXPERIMENT_LOG.md](EXPERIMENT_LOG.md).
The local launch/monitor scripts are in [tools/](tools/README.md).

## What is different here

In short; the reasons and the measurements are in
[docs/findings.md](docs/findings.md) and [docs/rdna4.md](docs/rdna4.md).

- **List calls are written down, not carried out, on the title's threads**
  (`VICTORY_THIN`): eight threads of ours translate them.
- **Submissions are prepared by a thread of ours and joined**
  (`VICTORY_ASYNC_SUBMIT`, `VICTORY_JOIN_PARTS`), with what can be spread over
  threads spread: refreshes, compares (AVX2), descriptor records, landings.
- **What shaders wrote comes back beside the write guards**, by the dwords that
  changed, on a thread of its own (`VICTORY_RELAY`, `VICTORY_LAND`).
- **Buffer fills that need bytes still on the card are done on the card**
  (`VICTORY_CARD_STEPS`) instead of waiting for it.
- **The title's writes are caught more cheaply**: one view opened at a fault,
  blocks that rest, places in the title's code that look before they write.
- **Textures go up on a copy queue of their own** and a slot shows one only
  after its upload ran, which also ended a device loss that came every 15
  minutes or so.
- **Boats float**: textures that shaders write and the title's CPU reads go
  back to title memory (from fxceless and Geckomacabre, on by default here).
- **Frame record and replay** with per-pass times and shader variants compared
  turn by turn ([docs/replay.md](docs/replay.md)).
- **RDNA4 keeps its skinning**: host-supplied buffer byte lengths replace the
  DXIL query that faults the AMD compiler, bad pipelines are optional to skip,
  and the panel shows CPU cost.

## Credits

This is a tree of other people's work with more on top. The history is kept,
and commits taken from elsewhere name the commit and its author.

- **[VIctory](https://github.com/Marvisak/VIctory)** by Marvisak and its
  contributors: the loader, the runtime services, the Direct3D 12 back end and
  the shader recompiler.
- **[fxceless/victory-fork](https://github.com/fxceless/victory-fork)**: the
  fork this one started from, and the people whose pull requests it carries.
- **[avatarmanz/VIctory-7900XTX](https://github.com/avatarmanz/VIctory-7900XTX)**:
  the tuned tree this fork starts from.
- **[DexNom/VIctory](https://github.com/DexNom/VIctory)**: ray tracing fixes,
  cube gradients, sparse textures.
- **[Belobug/VIctory-Belobug-AMD](https://github.com/Belobug/VIctory-Belobug-AMD)**:
  the ambient light idea, pipeline workers, and work by romainhedouin.
- **[FQY55kai/ZJOU-VICTORY](https://github.com/FQY55kai/ZJOU-VICTORY)**.
- **[myokex/victory-amd](https://github.com/myokex/victory-amd)**: the guard over
  every view of a page (with Spexivus, joroyt and tightfall), and Joshua Odom's
  reads into title memory.
- **Geckomacabre** and **cxy0072019-sketch**: the texture read-back.
- **[XCL](https://github.com/ivall/xcl)** (GPL-2.0-only) was read for how the
  same title behaves under another layer. The first-lane and wave experiments
  here were written anew behind off-by-default switches; no XCL source file is
  carried.
- This fork's changes were made with [Claude Code](https://claude.com/claude-code).

## License

GPL-3.0-or-later, as VIctory. See [LICENSE](LICENSE); the one file that is not
covered is named in [docs/asset-policy.md](docs/asset-policy.md). GPL-2.0-only
reference material was not copied into the tree; new code, including material
written after reading XCL or AnyPS5 work, is offered under GPL-3.0-or-later.

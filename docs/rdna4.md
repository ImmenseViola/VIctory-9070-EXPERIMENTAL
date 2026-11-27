# RDNA4 / RX 9070 notes (2026-11-26)

> This is the EXPERIMENTAL fork. These notes are inherited from the tuned tree;
> the switch that is on by default here and its A/B results are in
> [../EXPERIMENT.md](../EXPERIMENT.md) and
> [../EXPERIMENT_LOG.md](../EXPERIMENT_LOG.md).

These are the changes made after the tuned RX 7900 XTX build was ported to an
RX 9070. The 7900 XTX numbers and the larger speed work stay in
[findings.md](findings.md); this file is the AMD compiler and skinning work
that made the native build playable on RDNA4.

Test machine for this part:

- Radeon RX 9070, device `0x7550`, 16,191 MiB VRAM, wave lanes 32 to 64.
- Ryzen 5 7500F, 32 GB RAM, Windows 11 build 26200.
- Driver `amdxc64.dll` 8.18.10.0514, dated 2026-11-18.
- Series S profile, ports 1/2/5/6, 1920x1080 output, FSR upscaler 6.

## The failure

The title's `CSComputeSkinningTreeAnimVelocity_d2f99501_Wrapped` container
(hash `f16876929fa64f9f…`) made `ID3D12Device::CreateComputePipelineState`
fault with `0xc0000005` on this driver. Its sibling
`CSComputeSkinningTreeAnim_d2f99501_Wrapped` (`878933b499cfa14d…`) does the
same. The fault happened both while warming pipelines and inside the title.
The same driver had no such fault on the untuned baseline, so this is not an
assertion about all RDNA4 cards; it is the behavior of this card and driver.

The shader asks a buffer descriptor for its record count with DXIL
`getDimensions` after picking the descriptor from the console's view heap.
The translated shader left a `getDimensions` on a `ByteAddressBuffer` handle
built with `CreateHandleFromHeap`. On this driver that query, in that shape,
is what the compiler refuses.

A pristine worktree of upstream `a9400a6` also faults on
`the_record_count_of_a_structured_buffer_read_by_index`, so the raw
`getDimensions` hazard is not introduced by this fork.

## What was tried and rejected

- **Dropping in XCL's DXIL**: not possible. VIctory binds root constants and
  one root SRV (`t255 space1`); XCL binds six root UAVs (`u0-u5 space0`).
  `CreateComputePipelineState` rejects the mismatch with `0x80070057`.
- **Turning every `GetDimensions` into `undef`**: compiles, but is not a valid
  translation. Only diagnostic bits 2, 4, 8 and 16 remain, all off by default.
- **Removing `GetDimensions` globally**: also compiles, but texture sizes are
  still needed. Only fixed-table descriptors were kept on DXIL dimensions
  while the buffer case was isolated.
- **XCL-style first-lane lowering, wave32 metadata, integer raw loads, and
  skipping typed stores**: all compiled, none removed the fault. They remain
  as off-by-default switches (`VICTORY_FIRSTLANE_BALLOT`,
  `VICTORY_FORCE_WAVE32_META`, `VICTORY_RAW_LOAD_I32`,
  `VICTORY_SKIP_TYPED_STORE`) so the experiment can be repeated. Do not turn
  them on for normal play: XCL's global wave64 split in particular was a
  compile-hang workaround and can be much slower.
- **Global wave64 splitting or Rayon**: not ported. The target already has a
  persistent `wide*` worker pool.

## The permanent fix

The host already writes a table of view strides and addresses for every
console view slot. A third table now follows those two:

| Table | Constant | Contents |
|---|---|---|
| Strides and format kinds | `SLOT_STRIDES` | one dword per view slot |
| Title addresses | `VIEW_ADDRESSES = SLOT_STRIDES_COUNT * 4` | two dwords per slot |
| Byte lengths | `VIEW_SIZES = VIEW_ADDRESSES + SLOT_STRIDES_COUNT * 8` | one dword per slot |

`SLOT_STRIDES_COUNT` is `1 << 21`, so `VIEW_SIZES` is byte offset 25,165,824
in the root SRV. `SLOT_STRIDES_BYTES` covers all three tables. The host writes
the byte length whenever it writes a view address; a view with no byte length
writes zero. The shader clamps the heap index to `SLOT_STRIDES_COUNT - 1`,
shifts it left by two, adds `VIEW_SIZES`, and reads one dword with
`rawBufferLoad.f32`. The float is bitcast back to an integer.

The important correction during validation was that the index is a **byte**
offset: the table read is `VIEW_SIZES + slot * 4`, not `VIEW_SIZES + slot`.
With the wrong offset, the shaders read neighboring slots' lengths, which
explains the bad outdoor behavior in the first experimental build.

Only buffer descriptors whose slot the host can name (a table entry or a
descriptor picked from the view heap) take this path. A descriptor built from
root arguments has no host slot and keeps DXIL's query. Texture dimensions
are untouched.

`TRANSLATOR_VERSION` is now `3`:

- `1` to `2` invalidated old translations.
- `2` to `3` invalidated the experimental wrong-offset translations.

Do not reuse cache version 2 or the old `victory-7900-skin-cache` for a
version-3 binary. Re-run `translate --warm all` and `warm --used`.

Validation done on the final binary:

- `cargo build --locked --profile diag -p victory --features diagnostics`.
- All nine `victory-shader` `size_tests` pass, including
  `the_byte_length_of_a_picked_buffer_comes_from_the_hosts_table`.
- `victory translate <f168 container> --list --validate` translates and
  validates one compute program; `dxc.exe -dumpbin` shows no buffer
  `GetDimensions` and the `UMin(slot, 2097151) << 2 + 25165824` address.
- The viewport test `view_sizes_follow_the_view_addresses` checks that the new
  table does not overwrite strides or addresses.

## Visible result

With the final source and the offset fix, the skinning programs no longer
fault. In the earlier no-ped-flicker run the player reported:

- ped flickering gone, NPCs render correctly and are playable;
- indoor scenes about 21 FPS;
- the boat scene about 15 FPS average;
- outdoor areas 1 to 6 FPS with large stutters.

That outdoor number came from the build with the wrong size-table offset, and
from a cache warmed with experimental translations. It also included shader
recompilation and asset streaming. The final 480-second run with a fresh
version-3 cache recorded 149 world-frame samples: 18.27 FPS mean, 19.6 FPS
median, 0.1 FPS minimum. The first two minutes were the bad part (0.1-6.9
FPS): the log shows more than 1,600 pipelines being made and 54 ms a frame
spent waiting for them. Minutes 3 through 11 held about 18-21 FPS, with
several minutes at a 21.2 FPS median; the last two minutes were about 15 FPS,
matching the boat/late-scene report. GPU memory stayed around 11.7 GB of a
14.2 GB budget.

No `ERROR` lines, panic, device removal, or `0xc0000005` appeared in the final
log. The guard refused one pipeline from a bad list that had been written
before the host-size fix. The launcher was killed by the shell's 900-second
timeout after its 470-second screenshot; the game itself had not exited or
crashed. This supports the low-early-FPS hypothesis: it was mostly making
pipelines and streaming assets, not a permanent frame-rate regression. A
dedicated frame log with pipeline-creation and host-memory counters is still
the next step if the first two minutes need to be improved.

### What the later playthrough found

The user completed a mission in the boat scene at 16-22 FPS, then played into a
busy-street gunfight. There the frame rate fell to about 5 FPS even though no
pipelines were being made. The log explains it: `VICTORY_SKIP_WARM_BAD=1` was
reading a 31-shader bad list written against the old, wrong-offset
translations. It refused around 300 compute draws a frame, including the fixed
skinning shader `f16876929fa64f9f` and the broad `CS_RaytracingResolve_*`
family. The map and menus stayed at a solid 30 FPS, so this was not a global
GPU limit.

The bad lists are now read only when their first word is the current
driver/translator fingerprint, and the family-wide rule is gone. The
recommended switches no longer turn the guard on.

### Clean guard-off validation

The final binary was rebuilt and used for a fresh warm: 2,138 pipelines made, 0
bad, and 0 with no host pipeline. The following game session reported 3,951
shader-cache hits with 0 misses, so both books are now valid for translator 3.
In the boat scene, 30 world samples over about 2.5 minutes gave 17.61 FPS mean
and 18.7 FPS median, with no `refused [compute]` lines, no errors, and no
faults. The remaining “without a host pipeline” drops were all “a stage of the
ray-tracing structure builder, which is off”, not shader refusals. A 6,369-draw
frame held 11.3 FPS with 41.8 ms preparing and 23.4 ms on the GPU; the
stale-guard run had similar draw counts near 5 FPS. As a direct check,
`f16876929fa64f9f`, `1512b6b81c4072ed` and `29be03ccaa4e353a` were each
translated, given a host pipeline, and first-bound in the clean session.

The same playthrough reported: face textures and beards followed dialogue but
the model's lips did not move; eyes and sunglasses looked blueish; picture was
blurry in Series S mode; one vegetation piece was neon green; trees and grass
shimmered; and a dark shed showed artifacts around the character and dust.
Some of these may be the refused compute work; the rest are open visual bugs.

The refused work includes plausible causes for several of them:
`f16876929fa64f9f` / `878933b499cfa14d` skin the animation tree,
`1512b6b81c4072ed` is `ped_standard_eye`, and several
`CS_RaytracingResolve_*` containers cover retroreflection on eyes, sunglasses
and props. The guard also refused `29be03ccaa4e353a`
(`billboard_nobump:CS_RaytracingResolve_dcbebc34_Wrapped`) at startup. That
makes the lip and reflection symptoms likely consequences of missing compute.
The clean no-guard run binds those shaders normally; whether the artifacts are
gone is still awaiting the player's visual comparison. The dark-shed/dust
artifacts were not tied to a refused ambient shader, so they remain a separate
lead.

If the visual artifacts remain, the next experiments are, one at a time:
`VICTORY_WALLS_TRACE=1` for tree/grass/slod cadence, `VICTORY_HELPER_OWN=0`
for edge/quad artifacts, `VICTORY_AMBIENT=1` for the dark shed, and an
upscaler 6 versus 7 comparison for softness. Do not change `VICTORY_FFX_SCALE`.
If blue reflections survive the clean run, compare the `CS_RaytracingResolve`
and cube-gradient translations with `VICTORY_SHADER_SAVE` / `VICTORY_EMIT_DUMP`.

Tree/foliage flicker and occasional black glass are still present and are not
fixed by this work. After the release run the user played the boat mission
successfully at 16-22 FPS and reported that trees and grass still shimmer.

## Other RDNA4 changes in this release

- `CS_PedStandardSkinning_12_15f19d85_Wrapped` is restored. Earlier crash
  guards had skipped it and removed NPC skinning.
- The warm-bad guard can refuse exact pipelines and exact shader hashes when
  `VICTORY_SKIP_WARM_BAD=1`. Entries must carry the current driver/translator
  fingerprint; stale lists and the broad family rule are ignored. It is off by
  default: the 7900 XTX build compiles those programs.
- Shader registration no longer holds the global lock while a container is
  parsed and copied. Two threads may build the same container; only the one
  inserted is counted.
- The panel now shows system CPU use, VIctory's own CPU use, and panel cost
  alongside FPS, frame time, RAM and VRAM. It is enabled with
  `VICTORY_PANEL=1`.
- `VICTORY_SHADER_OVERRIDE=<dir>` loads `<hash>.dxil` in place of a
  translation. It is a driver-isolation hook, off by default.
- `VICTORY_DESC_WHY` was used while tracing descriptor roots and is not part
  of the release.

## Recommended switches for this card

Start from the tuned 7900 XTX settings and add these:

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

Use `--console series-s` when invoking `victory run` directly.

Do not use the experimental switches above, or
`VICTORY_SEND_CHANGED=1`, `VICTORY_BVH_BUILDER=1`,
`VICTORY_COPY_MODE=plain/none`, `VICTORY_PAGE_WRITES=1`,
`VICTORY_TEXTURE_FILL=0`, or `VICTORY_UNWATCHED_FRAMES>1`, for a release
build. They are either diagnostic, unproven, or the opposite of the tuned
configuration.

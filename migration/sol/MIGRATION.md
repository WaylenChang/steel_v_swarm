# Native presentation and resource pipelines — outstanding work

Read [AGENTS.md](AGENTS.md). Written implementations and source captures still
need current integrated acceptance. Shared shader translation and music envelope
semantics have separate Opus ownership; actor model construction is Models-owned.

## Seasonal resources and scenery

- [ ] **S1 — Complete world publication:** produce and qualify the complete
  original manifest, including ordinary seasons, both base assignments and
  authored campaign seasons. Enumerate current requirements and existing outputs
  from the tools; road-only resources cannot satisfy seasonal availability.
  Missing captures must never select an invented map or fallback season.
- [ ] **S2 — World storage/packing acceptance:** verify ordered chunk/numeric
  sidecars, exact float64 bits, raw/GZIP shapes/hashes, complete feature tables,
  cancellation and atomic publication. Bound peak memory through traversal and
  ResourceSaver publication; finish resource reload, complete rendered appearance
  and populated lifecycle checks on the full set, including actual tunnel cases.
  Existing Berlin spring/summer/autumn resources are partial inputs, not world-set
  certification. Refresh stale generator fingerprints before source reuse.
- [ ] **S3 — Terrain/scenery content:** finish source triangular terrain,
  dry-band/wet-grid, water/swamp, imagery, OSM facilities/buildings, habitat,
  complete biome orchestration and edge geometry capture. Retain original
  divider-band classification order, image-colour/border-band classifiers,
  slab/roof/portal metadata and pad anchors. Reject uncaptured classifiers.
  World geometry production stays here; authority LOS/support/traversal is Opus.
- [ ] **S4 — Animated scenery:** certify trains, articulated pivots, boundary
  facilities and waterfalls against source frame order, endpoints, parent frames,
  wind and capped/zero deltas. Finish wildlife, petals/leaves and aquatic
  bubble/fish/jelly/detritus/vessel/wake motion, Float32 write order, source
  constructor-time power/density budgets, route/habitat admission and per-instance
  resource isolation. Finish original starting-time-dependent scenery selection;
  do not regenerate populations on a later preference change.
- [ ] **S5 — Environment appearance:** finish cloud/fog-bank detail,
  precipitation, celestial bodies, deposits/scorch, contact effects,
  shoreline/underwater/waves/reflections and
  source wind/wave/gust/tide/ripple/vessel coupling. Bind the shared shader owner's
  accepted materials; certify weather style/low-power transitions and full
  seasonal rendered composition. Weather damage and hazards remain authority-owned.
- [ ] **S6 — Room resources/prebuild:** certify background loader retention,
  stale completion, cancellation, retry and missing-file recovery. Prebuilt worlds
  must key on the complete map/environment/architecture identity, ignore name-only
  edits and transfer one existing tree into the live physics space. Verify
  superseded builds, room leave, base/season/seed changes and no early processing
  or population. Shared loading/barrier handlers are Opus integration requests.

World workflow, from the repository root:

```powershell
node tools/bake_worlds.mjs --list-bundles
./tools/migrate_worlds.ps1 -Godot C:/path/to/godot_console.exe -Bundle berlin_1_autumn
godot --headless --path . res://tests/worlds.tscn -- --bundle=berlin_1_autumn
node --test tests/world_source.test.mjs tests/world_selection.test.mjs
```

The selected bundle is an example, not a substitute for completing the manifest.
The wrapper runs capture, source references and native packing sequentially.

## Audio playback and application binding

- [ ] **S7 — Source audio/native import:** certify decoded take order, full
  frames, normalization, mono/stereo routing, PCM/synthesis resources, retained
  BGM position/fallback, first gesture and independent sample RNG. Verify original
  sample rate/resampling, source codec failure and complete native audible output.
- [ ] **S8 — Mixer and voice lifecycle:** certify native SFX/BGM settings,
  panning, bus/filter order, initial dedup timestamp, cap reservation grace and
  playing-stream lifetime. Malformed legacy negative SFX polarity stays explicitly
  unavailable; do not convert it into positive gain. Music envelope correctness
  is an Opus-owned blocker, not a tolerance adjustment here.
- [ ] **S9 — Movement/location audio:** certify lazy permanent location beds,
  source channel allocation, noise/oscillator reconstruction, synchronized frame
  timing, filter modulation, tunnel/fluid/terrain queries and low-power ownership.
  Verify fade-out retention, driver suspension, buffer latency, thread shutdown,
  scheduling/performance and threaded Web export with actual mixer output.
- [ ] **S10 — Event/frame audio integration:** certify immediate local fire,
  cast/purchase reports, death/leave and remote events in their source order.
  Cover deduplication across snapshot/RPC delivery and all offline/ENet/WebSocket
  lifecycles, including source clock suspension and independent wall deadlines.

Relevant existing checks include `audio_*_suite.gd`,
`tests/audio_pan_render.tscn` and `tests/audio_move_render.tscn`. Source capture
and native sample checks do not replace audible/mixer/transport acceptance.

## Owner controls, camera and minimap presentation

- [ ] **S11 — Personal input state:** certify preference restoration, look and
  movement gates, multi-pointer ownership, tap/hold/drag/cancel boundaries,
  focus/overlay release and gyro watchdog/orientation. Do not double-rotate
  screen-axis sensor data or fabricate an identity pose from missing sensors.
  Physical hardware, hybrid-device/DPI detection and mobile exports remain open;
  synthetic decision fixtures cannot certify them.
- [ ] **S12 — View/scope/observer:** certify FPV/TPS/spectator camera state,
  source clipping/ring order, recoil composition, view-lock acquisition/cycling,
  previous-rendered projection, scope gradients/fog/blur/FOV easing and freeze/
  death/respawn transitions. Preserve source unknown observer resources. Models
  owns occlusion/rig geometry; Opus owns authority heading, acknowledgements and
  populated LOS/target contract changes.
- [ ] **S13 — Minimap:** certify full/vicinity windows, warmup/draw deadlines,
  original baked pixels, lane grades/dash/miter rules, labels, remembered bunkers,
  neutral exclusions and public entity markers. Finish persistent exploration,
  per-source occlusion shadows, soft masks, pulse/observer bypass and ordered
  SubViewport composition against browser raster sequences. World blocker query
  semantics and recipient vision remain Opus-owned. Relevant checks include
  `minimap_*_suite.gd` and `tests/minimap_fog_render.tscn`.
- [ ] **S14 — PiP:** certify original companion/decoy selection, stable order,
  ownership/death/lost-link gates, low-power limits, layout and camera offsets.
  Shared-world views must hide only their source body/cockpit while rendering,
  restore masks before copies and stop inactive viewports. Finish pixel,
  frame-order, performance and populated lifecycle/transport acceptance.
- [ ] **S15 — Local feedback:** certify optimistic cast/defense state,
  immutable rounded control publication, rising-edge notices, shared fire/cast
  warning clocks and replay rejection. Preserve zero-charge/zero-cooldown source
  eligibility and silent rejection gates. Complete owner movement/reaction and
  unbalance-notice binding from actual flight/sinking state, without inventing
  authority timers or client-side resource settlement.

## Projectile and screen effects

- [ ] **S16 — Reports/flight effects:** certify NPC shot styles, human/bot
  reports, local fan/remote plasma/lance/ion fallbacks, nearest current muzzle
  callbacks and private versus public shot cadence. Preserve pre-fire initial
  emitters, compressed reverse-order bursts, source crowding limits and contact
  star gates. Complete moving-shot interpolation, terminal owner-shell retirement,
  stale/same-clock snapshot suppression, geographic collision and immediate
  impact/prediction timing. These effects never repeat damaging settlement.
- [ ] **S17 — Impact/particles:** certify muzzle/contact/explosion layers,
  source fire/smoke/embers, texture/opacity/depth rules, pooling/oldest-first
  budgets, victim first-observation/healing/re-entry gates and guard peak rules.
  Finish original mechanical debris/comic-pop producers, bounce/shrink and
  ordered death/eviction behavior across both quality modes.
  Body-bound damage/guard materials are a Models contract; event producers are Opus.
- [ ] **S18 — Hit/death screen presentation:** certify hitstop order, damage
  bearings, immutable blood/glint drops, CSS decimal/gradient/blur composition,
  private vitality branches, hurt flash and reset/replay gates. Finish death
  camera ownership, ground/aerial sequences, early respawn cancellation, red-rim/
  whiteout raster, shop layering, configurable wipe behavior and blast feedback
  timing. Authority impulses and death reports remain Opus-owned. Use
  `tests/splat_render.tscn`, `tests/death_render.tscn` and affected transport cases.
- [ ] **S19 — Loot/fields/missiles:** certify native airdrop descent/landing,
  loot/relay/threat effects, cube/fog presentation, interpolated missile views,
  smoke/intercept/fracture timing and model-owner triangle queries. Finish
  source-conforming flood/pothole meshes and relay progress/strike visuals. Preserve
  silent removal versus genuine impact and source owner/round lifetime gates.
- [ ] **S20 — Campaign presentation:** certify original crawl/pan/zoom/skip,
  portrait/art fallbacks, UTF-16 radio timing, stable portrait ties, timer
  cancellation, transitions and victory transcript/replay. Campaign maps and
  authority stage/progress eligibility remain explicit external contracts.
- [ ] **S21 — Remaining quality consumers:** finish curated visual-style
  propagation, render-resolution scaling, world-text rebuilds and remaining
  low-power effect/audio consumers. Verify source constructor versus live-update
  boundaries, persistence and whole-scene rendering. Shared main-scene/renderer
  wiring and shader changes require exact Opus handoffs.

## Integration and handoffs

Run the current component references, real-driver resource/render checks and
root runtime gates for the affected behavior. Inspect existing transport case
switches for `-Loading`, `-Mobile`, `-Controls`, `-View`, `-Tps`, `-Pips`,
`-Minimap`, `-Projectiles`, `-Deaths` and `-Blasts`; invoke one switch per run.
Cross-owner changes stay as exact requests in this file until their owner pulls
them. Remove completed items; no dated checkpoints or copied validation history.

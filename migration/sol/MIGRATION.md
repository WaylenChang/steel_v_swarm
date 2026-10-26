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
  Use `node tools/world_publication_inventory.mjs --summary` to compare exact
  seasonal bundle names against the imported catalog. Detailed JSON includes
  per-bundle source identity, LFS/malformed/missing states and native binary
  presence; legacy names remain unselected. This availability inventory never
  qualifies sidecars, source provenance, native reload, rendered content or full
  match parity. Cover it with `tests/world_publication_inventory.test.mjs` and
  the existing `tests/world_selection.test.mjs`.
- [ ] **S2 — World storage/packing acceptance:** verify ordered chunk/numeric
  sidecars, exact float64 bits, raw/GZIP shapes/hashes, complete feature tables,
  cancellation and atomic publication. Bound peak memory through traversal and
  ResourceSaver publication; finish resource reload, complete rendered appearance
  and populated lifecycle checks on the full set, including actual tunnel cases.
  Keep compressed-candidate and existing-sidecar hashing streamed; never buffer
  a complete numeric sidecar just to determine its size or verify its digest.
  Run `tools/verify_world_source.mjs <bundle>` between capture/reuse and reference
  publication. It verifies the selected identity, contiguous chunks, every numeric
  dependency, streamed hashes and bounded GZIP extents without decoding complete
  numeric buffers into memory. A matching generator fingerprint never establishes
  that ignored/untracked sidecars are present. `tools/migrate_worlds.ps1` must stop
  before reference/native publication on any storage failure; this storage gate
  does not establish complete scenery, source provenance or rendered parity.
  Run `tools/verify_world_provenance.mjs <bundle>` separately for declared original
  input/asset bytes and both provenance fingerprints. Hash original files through
  bounded streams, reject paths/links outside the source root, and preserve
  declared missing-asset identity. `tools/migrate_worlds.ps1` runs this gate before
  references and again before native packing; source changes must stop publication.
  This gate does not establish generator freshness, extraction-helper/reference
  semantics, native shader fidelity or match parity. Keep the dedicated
  `tests/world_provenance.test.mjs` failure/immutability cases.
  Content-addressed mesh chunks also require length/hash validation before reuse;
  reject corrupt existing chunks without rewriting them. Cache verification by
  complete storage path: identical bytes can belong to both numeric and chunk
  namespaces. Legacy packing must
  dispose its writer on failure while retaining the original manifest and any
  already-published sidecars. Keep the child-process failure cases in
  `tests/world_source.test.mjs` alongside native reload coverage.
  Browser transfer, inline mesh chunks and final metadata publication must retain
  signed zero. `tools/source_json.mjs` uses native `JSON.rawJSON` and a copy-on-write
  adapter for the shared streaming publisher; reject unavailable native support
  instead of falling back to ordinary `JSON.stringify`. Capture fingerprints
  include the serialization helpers/storage writer, so prior captures require
  regeneration. Keep `tests/source_json.test.mjs` alongside storage regression tests.
  `node tools/source_json_capture.mjs` records original Chromium sphere-buffer bits;
  real-driver `tests/source_json.tscn` checks JSON, sidecar and native resource
  roundtrips. Retain its strict inline-number failures until the shared native
  number-decoding contract below is accepted; binary-sidecar success does not
  certify complete source numerics or full worlds. Interrupted capture chunks
  without a completed manifest never count as a published seasonal bundle.
  Publish marine shader includes through the native atomic publisher before the
  containing world, retaining their final content-addressed paths. Reuse requires
  byte-hash verification and a fresh native load; corrupt existing includes must
  remain untouched. `tests/world_shader_publication.tscn` checks dependency reload
  and retained-reader isolation, not marine shader pixels or complete worlds.
  Existing Berlin seasonal source captures are partial inputs, not world-set
  certification. Refresh stale generator fingerprints before source reuse.
  Stop browser producers before disposing an interrupted mesh writer. Close its
  live numeric handles and remove only its successfully opened raw/GZIP temporary
  paths; retain published content-addressed sidecars and rejected existing files.
  Writer temporary identities must remain unique within one process and clock
  tick. Keep `tests/world_source.test.mjs` disposal/ownership checks alongside
  native reload coverage; they do not qualify world content or publication.
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
  Preserve source double Euler state and evaluate unbounded rotor spin before
  native Float32 storage, retaining the original YXZ order and wind reversal.
  `node tools/scenery_rotor_capture.mjs` and real-driver
  `tests/scenery_rotor.tscn` cover original part/edge/waterfall frame programs,
  large fractional rotor phases and long wind reversals. Their synthetic geometry
  isolates motion; these checks do not qualify scenery meshes or populated worlds.
  `node tools/train_motion_capture.mjs` and real-driver
  `tests/train_motion.tscn` retain the original train-driver programs plus the
  captured Berlin autumn routes, including native PackedScene disk reload.
  Preserve their source/path fingerprints and existing transform tolerances;
  route replay does not certify train model geometry, random constructor-phase
  selection or complete seasonal-world retention.
  Wildlife construction retains source `write(0, weather)` and constructor
  activity, then advances its own staggered route states; do not substitute an
  elapsed wind clock at construction or rebuild populations for live preferences.
  `node tools/wildlife_native_capture.mjs` and real-driver
  `tests/wildlife_native.tscn` cover original habitat/motion programs, capacity
  prefixes, full/low budgets, constructor activity boundaries and saved instance
  buffer isolation. Synthetic probe geometry does not qualify original animal
  meshes, rendered habitats or complete seasonal population/transport retention.
  Wildlife bindings close on native root deletion while surviving staging
  detachment and reparenting. Weak observers match generation and instance ID;
  queued roots reject frames. Rebinding or retirement during terrain queries
  cancels the old writer before subsequent queries or instance writes, releasing
  private buffers and borrowed callbacks with closed owners retained.
  `node tools/wildlife_writer_capture.mjs` and real-driver
  `tests/wildlife_retirement.tscn` isolate the original writer with explicit
  state/limb probes; they do not execute RNG, route construction or integration,
  qualify authored animal geometry, or replace the full wildlife gate above.
  **Opus handoff:** reconcile `data/provenance.json` through
  `tools/import_source.mjs` with the original `public/js/rng.js` consumed by
  wildlife initialization. The full capture genuinely executes that dependency;
  retain its source guard and the failing `tests/wildlife_native.tscn` check.
  Acceptance requires matching source provenance and the complete original
  constructor, capacity, habitat and integration programs without dropping RNG
  inputs or substituting the scoped writer oracle.
  Aquatic school headings retain an unbounded source double angle; derive the
  quaternion before native storage. `node tools/aquatic_native_capture.mjs` and
  real-driver `tests/aquatic_native.tscn` cover original bubbles, detritus, fish,
  jellies, vessel/wake frames and private buffers, including large environment
  clocks. Their probe geometry does not qualify source model pixels or full worlds.
  Aquatic hosts and independent detritus controllers retain private buffers,
  particle phases and bubble RNG across staging transfers. Physical root/leaf
  deletion closes the matching weak binding; obsolete or duplicated observers
  cannot retire replacements. Queued owners reject updates, and retirement seals
  aliased system dictionaries before releasing owned point controllers, native
  vertex/instance buffers and RNG references. Real-driver
  `tests/aquatic_retirement.tscn` uses explicit state/point/sphere probes to check
  those lifetimes with closed controllers retained. It does not replace original
  factory/frame qualification, material pixels or full seasonal-world acceptance.
  **Opus handoff:** reconcile `public/js/rng.js` in shared provenance through
  `tools/import_source.mjs`. Aquatic constructors and original bubble recycling
  genuinely execute that dependency; retain the full producer and failing
  `tests/aquatic_native.tscn` guard. Acceptance includes all original aquatic
  initialization, reset RNG, large-clock motion and vessel/wake programs without
  omitting source inputs or changing the existing transform tolerances.
  `node tools/aquatic_point_capture.mjs` captures original PointsMaterial pixels
  through locally fulfilled, fingerprinted source modules. Run real-driver
  `tests/aquatic_render.tscn -- --source-capture` for the independent six-case
  oracle; the default shared-fixture guard remains unchanged. Preserve the failed
  point-pixel gate until the shared shader contract below is accepted.
  Petal landing uses original XYZ orientation with a fixed horizontal tilt and
  the accumulated double orbit phase; do not quantize that phase before evaluating
  its quaternion. `node tools/petal_native_capture.mjs` and real-driver
  `tests/petal_native.tscn` retain seasonal/prewarm budgets, grounding/fade/re-lift,
  directed invalid-input boundaries and original render matrices. Large seeded
  phase cases also compare normalized orientation independently of tiny petal
  scale. Declared crown/quad probes do not qualify original foliage/flower meshes,
  material pixels or complete seasonal world composition.
  Petal controllers preserve their captured clock/population and private material
  bindings across staging transfers. Native root deletion closes the weak binding;
  generation/observer identity guards isolate replacements and duplicated roots.
  Queued roots and retired owners reject later frames, and interrupted landing
  queries stop before later callbacks, cached landing writes or instance updates.
  Real-driver `tests/petal_retirement.tscn` checks these ownership boundaries with
  explicit grounded/quad probes and retained closed owners. It does not qualify
  source planning, motion, animal/foliage geometry or rendered seasonal worlds.
  **Opus handoff:** reconcile the original `public/js/rng.js` provenance through
  `tools/import_source.mjs` before full petal qualification. Both
  `public/js/petals.js::petalRnd` and the original field constructor consume that
  dependency; retain the full capture and `tests/petal_native.tscn` source guard.
  Acceptance requires the original seasonal/full-low planning, prewarm and all
  frame/transition programs without omitting RNG or loosening existing tolerances.
  Borrowed scenery pivots and train visuals retain their controllers across
  staging detachment/reparenting, without rebuilding phases or private materials.
  Native deletion closes the binding through a weak observer; match its binding
  generation and instance identity so old or duplicated observers cannot retire
  a replacement. Queued pivots/visuals reject later updates, and terminal
  controllers release source/node/material references and reject reconfiguration.
  Real-driver `tests/scenery_binding_retirement.tscn` replays original motion/train
  programs and checks transfers, rebinding, duplication, paused deletion and
  retained-controller material/curve release. Its waterfall quad and empty train
  model isolate ownership; they do not qualify authored geometry, complete world
  retention or populated transport/prebuild barriers.
  Scenery hosts also close on source-root deletion, sealing aliased owned-node
  lists, landmark records, private batch caches and child controllers before
  callbacks. Late frame/camp commands cannot advance shared clocks or revive the
  host; retirement never resets the module-global wind/wave/gust phases.
  Independent camp events retain both removals, while replacement roots stop old
  cache/frame continuations. World stepping rejects queued/deleted source roots
  and stops subordinate updates when a callback replaces the host binding.
  Real-driver `tests/scenery_host_retirement.tscn` retains source-program replay,
  staging/duplicate/rebind checks, native private-buffer isolation and resource
  release with closed hosts retained. Cache/geometry/callback probes and the
  fresh clock-only fixture contract do not establish complete scenery pixels,
  seasonal publication or populated world/transport/prebuild acceptance.
  Climb-arrow owners preserve their source flow phase and private instance buffers
  across staging transfers, then close terminally on native root deletion.
  Generation/observer identity guards isolate replaced and duplicated roots;
  queued roots and retired owners reject later updates. Release borrowed route
  references without clearing the authority caller's accepted roster.
  `node tools/climb_arrow_capture.mjs` runs the original arrow constructor,
  unit-bar geometry and update callback with declared route probes. Real-driver
  `tests/climb_arrow_retirement.tscn` retains its initial/long-clock transforms,
  unchanged matrix tolerance and native private-buffer ownership checks. This
  presentation-only capture executes no authority route planner and cannot
  qualify route admission, populated traversal, material pixels or complete worlds.
- [ ] **S5 — Environment appearance:** finish cloud/fog-bank detail,
  precipitation, celestial bodies, deposits/scorch, contact effects,
  shoreline/underwater/waves/reflections and
  source wind/wave/gust/tide/ripple/vessel coupling. Bind the shared shader owner's
  accepted materials; certify weather style/low-power transitions and full
  seasonal rendered composition. Weather damage and hazards remain authority-owned.
  Marine surface hosts close on native root deletion while staging transfers
  preserve private materials and incremental scan progress. Retain the unbound
  scan-only source-fixture contract; queued bound roots and retired owners reject
  updates. Root generation/observer identity guards isolate replacements. Water
  and ground-code callbacks may replace or retire the scanner; stop old row/cell
  continuations and global ripple updates after either boundary. Reflection
  visibility callbacks also stop later opacity writes and revision commits.
  Retirement releases terrain callbacks, wave buffers and private child bindings,
  but never resets module-global ripple slots, packets or cooldown.
  `node tools/marine_native_capture.mjs` captures the original extracted packet,
  hash and six scanner/ripple programs with their actual source dependencies;
  real-driver `tests/marine_retirement.tscn` replays them alongside native
  root/material ownership checks. Declared shader/quad probes isolate lifetime;
  they do not certify original marine shader pixels, authored surface geometry,
  full seasonal retention or transport/prebuild barriers.
  Native weather owners configure once, then close terminally on detachment.
  Prepare sky, light and private particle resources before world admission;
  reentrant publications retain the newest weather and original construction
  seed. Seal resource maps and lightning records before callbacks, stop stale
  property/frame writes and preserve independent strike batches. Unbind retired
  environments immediately, then drain queued sky resources through one native
  `frame_post_draw` callback independently of the closed node before final release.
  `node tools/weather_owner_capture.mjs` retains twelve original Node/Chromium
  precipitation-profile cases; real-driver `tests/weather_retirement.tscn` checks
  native profile bindings, interruption, expiry and retained-owner resource release.
  Also run it with `-- --live-exit` for active-owner application shutdown. Setter
  probes isolate property-boundary cancellation; these checks do not qualify
  original sky/cloud/fog/precipitation pixels, particle trajectories, authored
  lightning geometry or complete seasonal/transport acceptance.
  Fire flicker/drift uses the same local wall clock as loot, independently of
  incoming authority times and render deltas. Retain authored origin/scale doubles
  until final native Float32 writes; extinguished nodes keep their prior pose.
  The first visible smoke update disables depth writes and updates private source
  material metadata, preserving that state across later quench/recovery.
  `node tools/fire_clock_capture.mjs` and real-driver `tests/fire_clock.tscn`
  retain the original client/animation/weather functions, large clock phases,
  exact scalar/Float32 outputs and private packed-resource isolation. Their
  declared node probes use imported FX records; they do not qualify original
  constructor geometry, full shader pixels, populated worlds or transport delivery.
  Fire owners also close terminally on detachment. Complete private meshes,
  node indices, outline bindings and world pose before admission; reject late
  commands before sampling clocks. Sync/frame generations stop interrupted
  visibility, opacity and smoke-depth continuations. Retirement clears weather
  ownership without mutating the caller's dictionary, and world reuse acquires
  a fresh owner. Real-driver `tests/fire_retirement.tscn` replays the original
  frame oracle and checks reentrant cancellation plus deferred private-resource
  release while owners remain retained. It does not qualify the missing full
  constructor/shader/world or populated transport acceptance.
- [ ] **S6 — Room resources/prebuild:** finish populated seasonal-world retention,
  cancellation/retry and tree transfer in offline, ENet and WebSocket sessions.
  Isolated lifecycle fixtures cannot establish complete-world dependency retention
  or population/barrier behavior. Preserve request-time tickets across synchronous
  readiness callbacks and the complete map/environment/architecture identity;
  name-only edits must reuse one tree, with no early processing or population.
  Shared loading/barrier handlers are Opus integration requests.
  Resource retirement invalidates tickets and readiness immediately, then drains
  each native request independently of the retired node without waiting for its
  decoder. Pending `prepare()` calls return a signal that resolves to the native
  resource or cancellation; its waiter retains only a weak loader reference.
  Keep source requests active during SceneTree pause and preserve reentrant
  detach/reattach/replacement from progress callbacks. Run
  `tests/room_resource_retirement.tscn`, `tests/room_world_lifecycle.tscn` and
  WASAPI `tests/audio_loop_loading.tscn` for shared-drain regression coverage.
  Held decoder resources isolate lifecycle contracts; they do not certify actual
  seasonal scene content, populated-world retention or the transport barrier.
  Prebuild detachment also retires unfinished staging viewports, invalidates
  readiness and resolves pending transfers as cancellation. Reattachment requires
  a fresh request. Resource/build continuations and transfer waiters retain only
  weak owner references; destination loss must leave a valid ready tree reusable.
  Seal transfer ownership before native reparent callbacks, so a callback's fresh
  request cannot be cleared by the preceding transfer. Run
  `tests/prebuild_retirement.tscn` alongside existing room lifecycle checks.
  Recheck destination admission after synchronous reparent callbacks. A queued
  or detached destination cancels the transfer before processing is enabled;
  restore the same disabled world and its identity to staging only while the
  original cache generation remains current. Publish rollback ownership before
  reparent/readiness callbacks so fresh requests, clears and retirement win.
  Superseded cancelled transfers release their obsolete tree and viewport.
  Real-driver `tests/prebuild_transfer_cancellation.tscn` checks reuse without
  rebuilding, zero early process/physics ticks and replacement callbacks at
  destination entry, staging re-entry and rollback readiness. Its existing held
  fixture world does not certify seasonal geometry or populated transport barriers.
  Destination loss probes queue deletion at destination entry or detach during
  source exit. Removing an ancestor while its child is entering violates native
  tree notifications; use deferred deletion at that boundary.
  Held build signals exercise retirement without qualifying seasonal geometry.

World workflow, from the repository root:

```powershell
node tools/bake_worlds.mjs --list-bundles
node tools/world_publication_inventory.mjs --summary
node tools/verify_world_source.mjs berlin_1_autumn
node tools/verify_world_provenance.mjs berlin_1_autumn
./tools/migrate_worlds.ps1 -Godot C:/path/to/godot_console.exe -Bundle berlin_1_autumn
godot --headless --path . res://tests/worlds.tscn -- --bundle=berlin_1_autumn
node --test tests/world_source.test.mjs tests/world_selection.test.mjs
godot --headless --path . res://tests/world_storage.tscn
godot --headless --path . res://tests/room_world_lifecycle.tscn
godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy res://tests/seasonal_prebuild.tscn -- --bundle=berlin_1_autumn
```

The selected bundle is an example, not a substitute for completing the manifest.
The wrapper runs capture, source references and native packing sequentially.

## Audio playback and application binding

- [ ] **S7 — Source audio/native import:** certify decoded take order, full
  frames, normalization, mono/stereo routing, PCM/synthesis resources, retained
  BGM position/fallback, first gesture and independent sample RNG. Verify original
  sample rate/resampling, source codec failure and complete native audible output.
  Keep SFX clips content-addressed by PCM, full-precision normalization gains,
  stream format/rate/loop layout and original take/source identity. Publish the
  catalogue last through the atomic native resource publisher; never overwrite
  an existing fingerprint path or remove a prior catalogue's referenced clips.
  New sample libraries read a fresh catalogue snapshot and verify every clip
  before registering the complete batch. Synthesis, music fallback and movement
  also use verified content-addressed resources behind the same catalogue switch.
  One `BattleAudio` owner shares a lazy index snapshot across all consumers;
  late loads retain that generation, while acquisition can retry until a valid
  index exists. Regenerate legacy catalogues with `tools/import_audio.tscn`.
  Samples-only publication retains a complete index only when its source agrees
  and every retained dependency verifies; it cannot establish a missing full index.
  `tests/audio_catalogue.tscn` covers native reload, staged replacement and
  retained-reader isolation; `tests/audio_resources.tscn` checks original PCM and
  take order. `tests/audio_resource_catalogue.tscn` covers staged interruption,
  complete index replacement, delayed reads, exact resource identities, partial
  import retention and corruption rejection. These checks do not establish codec
  parity, actual device suspension, audible waveform parity or transport delivery.
- [ ] **S8 — Mixer and voice lifecycle:** certify native SFX/BGM settings,
  panning, bus/filter order, initial dedup timestamp, cap reservation grace and
  playing-stream lifetime. Malformed legacy negative SFX polarity stays explicitly
  unavailable; do not convert it into positive gain. Music envelope correctness
  is an Opus-owned blocker, not a tolerance adjustment here.
  Music, ambience, fallback and loop-player detachment is terminal: stop timers,
  release streams, disconnect envelopes and reject reattachment or late commands.
  Routing retirement must stop every live consumer before removing native buses,
  including SFX and movement workers. Track admitted children before callbacks;
  reentrant disposal cannot resume configuration or allocate another voice.
  `tests/audio_owner_retirement.tscn` checks native routing loss, paused detachment,
  held-decoder drainage and isolated original music/ambience/movement programs.
  Its isolated source gate does not replace full lifecycle provenance acceptance.
  Manager configuration and unlock must stop after synchronous retirement;
  queued owners/routes reject playback before touching deduplication or RNG.
  Reentrant voice/player admission cannot continue allocating, consume a take
  after cancellation or reserve a partially started voice. Manager retirement
  closes all consumers and emits one routing retirement notification.
  `tests/audio_manager_retirement.tscn` combines these native interruption cases
  with isolated original gate/count/sample programs from
  `data/audio_manager/fixtures.json`. Keep its exact numeric tapes and producer
  fingerprints; this dedicated capture does not discharge shared fixture gates.
- [ ] **S9 — Movement/location audio:** certify lazy permanent location beds,
  source channel allocation, noise/oscillator reconstruction, synchronized frame
  timing, filter modulation, tunnel/fluid/terrain queries and low-power ownership.
  Verify fade-out retention, driver suspension, buffer latency, thread shutdown,
  scheduling/performance and threaded Web export with actual mixer output.
  Reuse panning coefficients only for an exactly unchanged double control value;
  retain per-sample evaluation during automation and the existing buffer latency.
  Movement owners and voices retire permanently on tree exit; reattachment must
  reject configuration rather than reconnecting signals to stopped DSP state.
  Use a fresh owner for new playback. Stopped workers release pending mixer
  references and explicitly reject later submissions; the caller must release
  the rejected voice. Deferred startup and reentrant registration callbacks cannot
  reactivate retiring nodes or allocate new native voices after queued deletion.
  Run WASAPI `tests/audio_move_retirement.tscn` and `tests/audio_move_render.tscn`
  alongside source lifecycle checks. Native frames and shutdown probes do not
  certify audible waveform parity, device suspension or threaded Web delivery.
  Service permanent voices in admission order with a one-millisecond worker
  poll. Failed middle voices must not skip later voices; submissions during a
  service pass join its next pass. `tests/audio_move_retirement.tscn` verifies
  these races with a real worker. Run `tests/audio_move_render.tscn -- --stress`
  for 32 repeated 150 ms UI interruptions with unchanged continuity/skip checks.
  One WASAPI device configuration does not certify other drivers/rates, sustained
  CPU contention or platform delivery. Keep the two-period startup budget aligned
  to Godot's native 128-frame resampler refills instead of truncating it to the
  driver period. `tests/audio_generator_buffers.tscn` reproduces the former
  480-frame driver's 64-frame shortfall at an off-block cursor and verifies
  native refills across driver sizes. Do not hide scheduling failures by
  increasing the budget, changing coefficient math,
  branch order or automation clocks, or relaxing strict underrun checks.
  Requalify the block size against the installed engine's native
  [resampler contract](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/audio_stream.h)
  on engine upgrades; failure diagnostics must retain current output skips,
  playback position, free ring frames, unread source captures and maximum service
  gaps. Keep measured per-call time alongside those cursors in native captures.
- [ ] **S10 — Event/frame audio integration:** certify immediate local fire,
  cast/purchase reports, death/leave and remote events in their source order.
  Cover deduplication across snapshot/RPC delivery and all offline/ENet/WebSocket
  lifecycles, including source clock suspension and independent wall deadlines.
  `tests/audio_context_clock.tscn` compares the silent SFX context against an
  independent, active native PCM bus beyond bus auto-disable, through paused
  zero/slow/fast SceneTree scales and bounded capture overflow. Preserve exact
  native frame deltas. This does not qualify physical driver suspension, rate
  changes or event delivery; retain the distinct source-context and wall clocks.

Relevant existing checks include `audio_*_suite.gd`,
`tests/audio_pan_render.tscn` and `tests/audio_move_render.tscn`. Source capture
and native sample checks do not replace audible/mixer/transport acceptance.

Audio workflow, from the repository root:

```powershell
node tools/audio_mixer_references.mjs C:/path/to/steel_vs_swarm
node tools/audio_lifecycle_references.mjs C:/path/to/steel_vs_swarm
node tools/audio_manager_references.mjs C:/path/to/steel_vs_swarm
godot --headless --path . res://tools/import_audio.tscn
godot --headless --path . res://tests/audio_resources.tscn
godot --headless --path . res://tests/audio_lifecycle.tscn
godot --headless --audio-driver WASAPI --path . res://tests/audio_loop_loading.tscn
godot --headless --audio-driver WASAPI --path . res://tests/audio_owner_retirement.tscn
godot --headless --audio-driver WASAPI --path . res://tests/audio_manager_retirement.tscn
godot --headless --audio-driver WASAPI --path . res://tests/audio_pan_render.tscn
godot --headless --audio-driver WASAPI --path . res://tests/audio_move_render.tscn
```

`data/audio_mixer.json` is a dedicated Sol oracle, independent of the shared
fixture registry. Regenerate it after changing its source captures or generators;
its tool fingerprints normalize text line endings. Mixer capture covers the
active device rate; captured reference rates alone do not certify other native
device rates, codec/resampling behavior, audible output or populated transports.
Native audio publication must keep using the atomic resource publisher.
`data/audio_lifecycle.json` retains the original streamed-state, ambience-envelope,
movement and location/source-selection oracles. It does not include the shared
music envelope adapter. Retiring a pending audio player must not wait for decode;
drain the request without capturing the retired node or consuming another
player's completion. Keep imported loop properties immutable and retain each
player's position when pausing/resuming.

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
  Fog opacity must retain the original CSS ease-out curve and reversal-shortened
  durations, including repeated reversals, unchanged targets and zero-progress
  cancellation. Native tween writes must reach shader uniforms in the same frame.
  `node tools/scope_transition_capture.mjs` and real-driver
  `tests/scope_transition.tscn` compare original browser transitions and native
  uniforms; these checks do not certify scope gradient/blur pixels or complete
  frame-order, freeze/death and populated view integration.
  `node tools/scope_raster_capture.mjs` and real-driver `tests/scope_raster.tscn`
  retain original CSS/HUD callback composition over controlled browser backgrounds.
  Keep the strict raster failures and exact byte witnesses in `build/scope_raster/`;
  transition-state success cannot discharge the shared ring-color, backdrop-blur
  and raster-comparator contracts below.
  Spectator pose writes preserve the original Y-then-X rotation from double
  angles before native storage. `node tools/spectator_native_capture.mjs` and
  real-driver `tests/spectator_native.tscn` retain original camera/state/HUD
  programs, actual Three camera quaternions and native exit ownership probes.
  Unknown remote magazines and movement resources remain null. These checks do
  not qualify populated ray queries, actor pixels, recipient publication or the
  shared main-to-camera angle transfer contract below.
  Lock-glow hit decay retains millisecond subtraction before division by 200;
  ring rotation derives its quaternion from the double phase before native
  storage. `node tools/lock_glow_capture.mjs` executes the original constructor
  and render callback under Node and Chromium, retaining both numeric results;
  Chromium is the browser-state oracle. Real-driver `tests/lock_glow.tscn`
  compares exact double states, native Float32 poses/material values, ring
  orientation and private resource release. Keep its strict scalar gate open
  until the shared pulse-sine contract below is accepted. The shared texture
  probe, measured-dimension probe and component states do not qualify glow
  texture pixels, actor bounds, populated targeting or full frame composition.
- [ ] **S13 — Minimap:** certify full/vicinity windows, warmup/draw deadlines,
  original baked pixels, lane grades/dash/miter rules, labels, remembered bunkers,
  neutral exclusions and public entity markers. Finish persistent exploration,
  per-source occlusion shadows, soft masks, pulse/observer bypass and ordered
  SubViewport composition against browser raster sequences. World blocker query
  semantics and recipient vision remain Opus-owned. Relevant checks include
  `minimap_*_suite.gd` and `tests/minimap_fog_render.tscn`.
  `node tools/minimap_native_capture.mjs` and real-driver
  `tests/minimap_native.tscn` retain original window/marker/cadence/lane/vision
  programs and atlas ownership. Run real-driver
  `tests/minimap_fog_render.tscn -- --source-capture --full-raster` for complete
  composition and persistent-mask sequences. The existing probe tolerance remains
  four bytes; probe-only success does not discharge the full-image gate.
  Diagnostics are retained under `build/minimap_fog/`. Controlled canvas inputs
  do not qualify the actual baked terrain base or populated recipient/query state.
- [ ] **S14 — PiP:** certify original companion/decoy selection, stable order,
  ownership/death/lost-link gates, low-power limits, layout and camera offsets.
  Shared-world views must hide only their source body/cockpit while rendering,
  restore masks before copies and stop inactive viewports. Finish pixel,
  frame-order, performance and populated lifecycle/transport acceptance.
  Visibility loss through either the control or its ancestors, detachment and
  retirement must immediately disable updates, release the shared world and
  restore temporary layers. Reattachment requires fresh selection before drawing.
  `node tools/pip_capture.mjs` and real-driver `tests/pip_native.tscn` retain
  original selection/render decisions, layout and native lifecycle/pixel-isolation
  checks. Primary-color probes isolate camera masking; they do not substitute
  source model pixels, full-scene composition or populated transport acceptance.
- [ ] **S15 — Local feedback:** finish integrated immutable rounded control
  publication, rising-edge notices and replay rejection. Keep the source
  eligibility, silent rejection, optimistic cast/defense and shared fire/cast
  clock contracts covered by `tests/local_controls.tscn` and
  `tests/audio_lifecycle.tscn`. Complete owner movement/reaction and
  unbalance-notice binding from actual flight/sinking state, without inventing
  authority timers or client-side resource settlement.

Local-feedback references are captured with `node tools/local_controls_capture.mjs`
and `node tools/audio_lifecycle_references.mjs`. Run the corresponding native
scenes before integrated acceptance; neither scene certifies populated snapshots.

## Projectile and screen effects

- [ ] **S16 — Reports/flight effects:** certify NPC shot styles, human/bot
  reports, local fan/remote plasma/lance/ion fallbacks, nearest current muzzle
  callbacks and private versus public shot cadence. Preserve pre-fire initial
  emitters, compressed reverse-order bursts, source crowding limits and contact
  star gates. Complete moving-shot interpolation, geographic collision and immediate
  impact/prediction timing. These effects never repeat damaging settlement.
  Keep owner-pose clocks monotonic and terminal deadlines nondecreasing;
  `tests/projectile_lifecycle.tscn` covers stale/equal-clock packets before and
  after terminal-guard reclamation. Populated transports still require acceptance.
  Native owner exit must clear active rounds, visual-shell model references,
  tracers and every model pool; late calls cannot resume that owner. Reattached
  worlds acquire a fresh presentation owner. Seal record removal before native
  visibility callbacks and stop continuations after collision/impact retirement.
  Keep the original per-variant pool bound and LIFO order, dispose overflow and
  reset root scale on reuse. Regenerate `data/projectile_presentation.json` with
  `node tools/projectile_owner_capture.mjs`; never manually retune its bound.
  Real-driver `tests/projectile_owner_retirement.tscn` verifies current original
  acquisition/drop programs, ordinary/hit/range flight, actual packed models and
  interrupted native ownership. These cases do not qualify all projectile styles,
  moving snapshot interpolation, complete pixels or populated transport behavior.
  Tracers retain one two-vertex dynamic ArrayMesh and private material across
  reuse. Update its culling override with the vertex buffer; native raster probes
  must still draw after endpoints move outside the original surface bounds.
  Release clears the old trace record before visibility callbacks and may return
  a line only once. Preserve original double TTL/age accumulation and fade order.
  The ownership scene includes source endpoint/frame programs, exact scalar bits
  and real-driver buffer/culling-pixel checks. It requires a rendered session.
  Verify retired buffers and private materials after deferred destruction and a
  completed rendered frame, including lines that were actually visible.
  Original tracer prewarm/free-stack bounds remain unqualified until the pool
  provenance contract below is resolved. Preserve the shared oldest-first
  `FX_MAX` budget and reverse fade/expiry order across
  `ProjectilePresentation.traces` and `CombatEffects.effects`, after visual-shell
  movement. Source crowding gates count both owners. Regenerate the scoped oracle
  with `node tools/effect_order_capture.mjs`; real-driver
  `tests/presentation_effect_order.tscn` checks mixed insertion, zero-delta trimming,
  exact lifetime/fade scalars, both quality gates and reentrant owner retirement.
  Its unbuilt-world and callback probes do not qualify full effect pixels,
  original tracer pool limits or populated transport behavior.
- [ ] **S17 — Impact/particles:** certify muzzle/contact/explosion layers,
  source fire/smoke/embers, texture/opacity/depth rules, pooling/oldest-first
  budgets, victim first-observation/healing/re-entry gates and guard peak rules.
  Finish original mechanical-debris random ordering, lossless instance colors,
  source comic texture import, bounce/shrink and ordered death/eviction behavior
  across both quality modes. `node tools/destruction_capture.mjs` captures the
  original particle states/textures; `tests/destruction_native.tscn` retains the
  strict native checks (`-- --comic` or `-- --mechanical` selects one family).
  Body-bound damage/guard materials are a Models contract; event producers are Opus.
- [ ] **S18 — Hit/death screen presentation:** certify hitstop order, damage
  bearings, immutable blood/glint drops, CSS decimal/gradient/blur composition,
  private vitality branches, hurt flash and reset/replay gates. Finish death
  camera ownership, ground/aerial sequences, early respawn cancellation, red-rim/
  whiteout raster, shop layering, configurable wipe behavior and blast feedback
  timing. Authority impulses and death reports remain Opus-owned. Use
  `tests/splat_render.tscn`, `tests/death_render.tscn` and affected transport cases.
  Preserve source camera setup outside measured death-method RNG consumption.
  `node tools/death_overlay_capture.mjs` captures camera states and CSS;
  `tests/death_native.tscn` checks component state without replacing shared camera
  ownership/respawn integration. Run `tests/death_render.tscn -- --source-capture`
  on the real driver for independently fingerprinted CSS raster acceptance.
- [ ] **S19 — Loot/fields/missiles:** certify native airdrop descent/landing,
  loot/relay/threat effects, cube/fog presentation, interpolated missile views,
  smoke/intercept/fracture timing and model-owner triangle queries. Finish
  source-conforming flood/pothole meshes and relay progress/strike visuals. Preserve
  silent removal versus genuine impact and source owner/round lifetime gates.
  Mine visibility retains the original zero-initialized absolute throttle clock,
  strict 0.12 s wall-time interval and three-argument compensated distance before
  sight/opacity decisions. Native Float32 observer/anchor components enter double
  subtraction directly; a Float32 vector length changes edge behavior. Preserve
  hidden opacity and per-instance material isolation. `node tools/mine_view_capture.mjs`
  executes the original controller under both Node and the original Chromium
  runtime; real-driver `tests/mine_view.tscn` retains exact distance/time bits,
  near-threshold states and world clock binding. Constructor geometry/shading and
  terrain height probes do not qualify original mine shape, imagery-derived
  camouflage, complete world coordinates, trigger settlement or transport delivery.
  Mine owners retire terminally on detachment and reject queued/late calls before
  clock providers, throttle reservation or model acquisition. Prepare private
  meshes and world pose before admission; seal the entire roster before terminal
  visibility callbacks. Reentrant synchronization and eligible view updates
  supersede old opacity/visibility continuations. World reuse acquires fresh
  owners. Real-driver `tests/mine_retirement.tscn` replays the original visibility
  oracle and checks interrupted admission/removal, clock callbacks, nested view
  updates and deferred private-resource release with closed owners retained.
  It does not qualify the uncaptured imagery/geometry or populated round delivery.
  Missile retirement is terminal and idempotent. Seal it before fracture callbacks,
  stop interrupted observation/model continuations, and release packed models,
  persistent damage children, copied materials and private ray buffers even while
  the closed owner remains retained. Reattachment requires a fresh owner.
  `node tools/missile_owner_capture.mjs` and real-driver
  `tests/missile_owner_retirement.tscn` retain original interpolation/smoke/removal
  programs plus native admission, damaged-owner and deferred-resource checks.
  Declared source geometry/damage probes do not qualify missile shape, damage
  semantics, complete pixels, ray triangles or populated transport delivery.
  **Models — `scripts/missile_view_ray.gd`:** reject retired/queued owners before
  reading global transforms, model nodes or persistent damage geometry. Acceptance:
  ray queries during a reentrant terminal fracture callback, after retirement and
  after tree detachment return no hit without dereferencing released resources.
  Fog circles/rings retain original expanded triangle order, normals and exact
  Float32 UV writes, including native resource reload. Reuse immutable meshes by
  exact radius parameters while retaining private per-fog opacity materials.
  `node tools/fog_geometry_capture.mjs` and real-driver
  `tests/fog_geometry.tscn` retain the actual source constructor and all six layers.
  Buffer/material checks do not qualify composed pixels, clocks or capacity.
  Fog owners close terminally on tree exit and reject late geometry acquisition.
  Complete all layers, pose and membership before native admission; seal removals
  before visibility callbacks and stop superseded synchronization after admission,
  removal or ally replacement. Retirement clears the immutable mesh cache while
  deferring native child destruction; world reuse requires a fresh owner.
  Real-driver `tests/fog_retirement.tscn` reuses the original geometry oracle and
  checks reentrant interruption plus root/material/cache release with retained
  owners. These lifecycle checks do not resolve the delivery contract below.
  **Opus — `scripts/main.gd` fog delivery contract:** reconcile the current
  snapshot-derived `BattleWorld.sync_fogs` age/expiry with original `fog_spawn`
  receipt and render-frame effect deltas. Original fog visuals belong to the
  same oldest-first `FX_MAX` list as tracers and other effects; authority duration
  must not silently replace that client lifetime. Acceptance: zero/capped frame
  deltas, paused authority clocks, late observation and mixed-effect eviction
  retain the original birth/fade/removal sequence before full fog qualification.
  Keep loot bob/airdrop descent on the local wall clock, independent of incoming
  authority clocks; creation and frame updates must use that same time base while
  rotation still consumes the source frame delta. Accumulate rotation in double
  state instead of feeding Node3D Float32 Euler values back into later updates.
  Derive quaternions before native storage so large source angles do not lose
  their fractional phase. Validate exact source IEEE-754 phase/delta bits and
  rendered orientation rather than canonicalized native Euler representations.
  `node tools/loot_clock_capture.mjs`
  and real-driver `tests/loot_clock.tscn` cover the original methods and world
  binding, not complete loot geometry or populated pickup/transport settlement.
  The clock producer executes only the captured original constants/functions;
  do not import the entire source data module or its unrelated RNG dependencies.
  Retain strict hashes for every executed source input and the fixture writer.
  Run the same programs in Node and original Chromium, require matching double
  phase/landing tapes, and publish the browser's pose outputs. Preserve the
  declared constructor probes and all long-rotation/zero-clock cases; this gate
  still cannot establish source constructor geometry or complete rendered pixels.
  Collectible owners close terminally on detachment; world reuse acquires fresh
  owners. Seal all entry references before visibility callbacks, prepare pose
  and private outline bindings before admission, and stop superseded sync/frame
  continuations. Existing IDs retain their original first-observation metadata;
  removal and later reuse create fresh objects. `node tools/collectible_owner_capture.mjs`
  executes the original constructors and snapshot/frame methods for eighteen
  programs; real-driver `tests/collectible_retirement.tscn` checks those states,
  reentrant replacement/retirement and deferred root/private-material release.
  Declared source geometry/toon/outline and terrain probes do not qualify shape,
  shading, complete world coordinates, pickup settlement or transport delivery.
- [ ] **S20 — Campaign presentation:** certify original crawl/pan/zoom/skip,
  portrait/art fallbacks, UTF-16 radio timing, stable portrait ties, timer
  cancellation, transitions and victory transcript/replay. Campaign maps and
  authority stage/progress eligibility remain explicit external contracts.
  Retain generation checks across synchronous `finishing` listeners; cancelled,
  replaced, detached or retiring cinematics must not schedule old completion work.
  Empty sequence replacement disposes the previous scene before completing.
  `tests/campaign_lifecycle.tscn` covers these lifecycle contracts independently
  of the unresolved native story-art import and complete visual composition.
  Exit opacity applies once to the complete CanvasGroup, using the captured
  original curve. A separate native wall timer retains the 650 ms completion
  deadline; completing or pausing the visual tween cannot settle it early.
  Detachment invalidates pending completion and requires fresh playback after
  reattachment. `node tools/campaign_transition_capture.mjs` and real-driver
  `tests/campaign_transition.tscn` retain the original finish method/CSS, deadline
  boundaries and layered opacity rasters. Controlled color layers do not qualify
  actual story art, blur/vignette filters or complete cinematic composition.
  Art opacity retains the original 0.9 s cubic-bezier(0.4,0,0.2,1), stable scene
  order and independent state for every still-visible scene during rapid
  three-way changes. `node tools/campaign_art_capture.mjs` and real-driver
  `tests/campaign_art.tscn` retain original construction/selection methods,
  reversals, unchanged targets and first-frame layered color probes. Native
  SubViewports isolate the groups from the containing presentation CanvasGroup;
  use premultiplied blending with opacity applied to RGBA, and stop retired or
  transparent render targets. Preserve the strict frame-7 comparator failure
  and byte witness below. Declared colors do not qualify actual art decoding,
  fallback pixels, blur, framing, populated transitions or performance.
  Foreground transforms retain the original 0.25 s cubic-bezier(0.1,0.8,0.3,1),
  whole-transform reversal shortening and unchanged-target behavior. Serialize
  source camera targets through `CssDecimal` before comparison; keep interpolation
  tuples and Bezier controls in double precision until native image storage.
  Resize reapplies the current pose without restarting its transition, while the
  blurred background remains fixed. `node tools/campaign_pose_capture.mjs` and
  real-driver `tests/campaign_pose.tscn` retain original camera functions and
  unrounded typed CSS samples for every original camera/orientation. Browser
  completion states also verify settled native coordinates. These probes do not
  qualify actual art/framing pixels, per-frame crawl/target delivery, complete
  populated cinematic composition or platform/DPI behavior.
  Crawl uses its own monotonic wall-frame timestamp, updated even while paused
  or at the scroll limit. Preserve the original 0.1 s delta cap, strict pause
  deadline and each DOM scroll write/read; hidden fractional accumulation changes
  the source's frame-rate-dependent pixel quantization. Fresh playback resets
  both the retained viewport position and frame clock. Original browser probes
  at scales 1/1.25/1.5/2 retain the same integer logical-pixel readback.
  `node tools/campaign_crawl_capture.mjs` and real-driver
  `tests/campaign_crawl.tscn` retain original controller methods and real browser/
  native scroll containers, including half-pixel, pause, gap, limit and replay
  cases. Declared geometry isolates scrolling; it does not qualify narrative
  layout, complete frame ordering, camera-target delivery or hardware DPI behavior.
  Camera-target delivery follows the original frame branch: paused or saturated
  automatic scrolling does not reevaluate focus solely because section geometry
  changed. Explicit scroll/resize producers retain their own focus updates.
  `node tools/campaign_delivery_capture.mjs` and real-driver
  `tests/campaign_delivery.tscn` connect actual scroll controls to original
  nearest-section/camera functions, including gaps, ties, zero heights and
  per-scene serialized targets in both orientations. Controlled section geometry
  does not certify live typography, event-loop/render timing or full cinematics.
  Initial playback clamps the requested chapter once, before initial selection
  and the deferred jump. Layout must not deliver camera targets before that
  source callback. A middle-chapter jump retains the requested selection even
  when scroll clamping or zero-height sections makes focus choose another scene;
  retain any camera target already delivered to that other scene.
  `node tools/campaign_start_capture.mjs` and real-driver
  `tests/campaign_start.tscn` retain original `play`/focus/camera methods, browser
  scroll quantization, both orientations, out-of-range indexes and empty/clipped
  section geometry. Declared geometry and initial native layout probes do not
  certify narrative layout or full event-loop/render ordering.
  Skip input retains original millisecond clocks and strict 650/350 ms hold/tap
  boundaries. Cancelled or unpaired releases never become taps; finish-button
  exclusion follows the touch origin, and release/cancel never extends the crawl
  pause. Replacement callbacks must not inherit retired input state.
  `node tools/campaign_input_capture.mjs` and real-driver
  `tests/campaign_input.tscn` compare original handlers and directed native
  replacement callbacks. Event-target doubles and direct native input dispatch
  do not qualify hardware touch bundling, GUI button activation, source image
  buffering, crawl/art pixels or complete campaign/transport acceptance.
  Hold feedback retains the original zero-coordinate fallback and viewport clamp,
  circumference targets, CSS ease/linear curves and reversal-shortened durations.
  Restarting an active hold resets progress without restarting its opacity fade.
  `node tools/campaign_hold_capture.mjs`, real-driver
  `tools/import_campaign_hold.tscn` and `tests/campaign_hold.tscn` retain the
  dedicated source identities and atomically published lossless native backplate.
  Keep PNG alpha-border processing out of that resource. Its isolated SubViewport
  and premultiplied texture opacity must also work inside the outer presentation
  group; `tests/campaign_hold_render.tscn -- --nested-presentation` retains that
  composition gate. Scope and hold consumers
  share `CssTransition`, with `tests/scope_transition.tscn` retaining its source
  oracle. Run `tests/campaign_hold_render.tscn` for the seven original pixel cases;
  static/group controls pass but dynamic native SVG stroke coverage remains an
  open shared-renderer contract below. Do not certify full cinematic pixels,
  fractional/DPI placement, hardware input, export or performance from these probes.
  Prologue playback continues while native image/font cache attempts run. Gesture
  skipping waits for every attempt; the explicit finish button retains its source
  bypass. Failed attempts count toward progress, not asset availability. Preserve
  independent 1800 ms warning deadlines, generation checks and decoder drains
  across replacement/exit, including pause and zero gameplay speed. Original model
  warming currently has an empty base manifest; reject nonempty/custom manifests
  until their native preload contract is published. Keep retained successful
  resource-cache entries separate from cancelled owners and private scene state.
  `node tools/campaign_buffer_capture.mjs` and real-driver
  `tests/campaign_buffer.tscn` retain original cache/error/skip programs, native
  resource requests, held-decoder retirement and warning timers. Controlled art
  layers do not qualify actual story decoding, warning CSS/flash appearance,
  complete cinematic pixels or hardware input. Successful-image readiness and
  complete first-play loading still require the shared story-encoding contract
  below and publication of the remaining preload images (`assets/logo_flat.png`
  and `assets/loading/`) through Opus-owned `tools/import_source.mjs`, preserving
  the original paths, decoded bytes and explicit failure behavior.
  Automatic radio retains original empty-scene, UTF-16 timer, replacement/clear,
  viewer-relative portrait/guest and single-speaker endpoint behavior. A hidden
  portrait endpoint stays hidden when receiving a speaker update.
  `node tools/dialogue_native_capture.mjs` and real-driver
  `tests/dialogue_native.tscn` compare original Dialogue methods and actual native
  character/mech asset bindings. DOM probes observe mutations without qualifying
  CSS layout/filter pixels. Manual `next()` is source storybook inspection only;
  live gameplay must remain automatic. Finish original portrait opacity/filter
  transitions and complete radio/transcript composition before visual acceptance.
  Radio and transcript callbacks retain absolute monotonic wall deadlines,
  including native timeouts that arrive early. Gameplay speed and SceneTree pause
  must not freeze their timers or the radio retirement tween. Reject duplicate
  delivered callbacks and retired-generation callbacks before scheduling work.
  `tests/dialogue_clock.tscn` checks strict deadline edges, replacement, actual
  paused zero/slow/fast timers and bar retirement; the original dialogue fixture
  retains every automatic line duration. These clock checks do not qualify radio
  mount/unmount CSS curves, transcript reveal motion or complete overlay pixels.
  Radio mount/unmount retains the original 320/400 ms ease-out/ease-in curves,
  14/10 px offsets and separate 420 ms removal deadline. Animate an isolated
  premultiplied SubViewport through Sprite2D so fractional translation samples
  the complete group without GUI pixel snapping. Hidden and retired groups must
  stop drawing, and replacement must cancel the old entrance/exit motion.
  `node tools/dialogue_motion_capture.mjs` and real-driver
  `tests/dialogue_motion.tscn` retain unrounded CSS Typed OM values and original
  removal methods. Controlled overlapping color layers qualify group animation,
  not actual radio layout, portrait filters, typography or complete overlay pixels.
  Transcript rows retain original integer-millisecond stagger arithmetic and
  260 ms ease-out group opacity/6 px translation, independent of gameplay pause.
  Clear cancels pending reveals without hiding rows already revealed. Removing
  a row retires its tween and isolated render target before deferred destruction.
  Nearest scrolling uses transformed row bounds, oversized-row rules, current
  scrollbar ranges before native layout catches up, and visible inner bounds
  when propagating through multiple scroll ancestors.
  `node tools/dialogue_transcript_capture.mjs` executes original `Dialogue.scene`
  in Chromium; real-driver `tests/dialogue_transcript.tscn` retains original
  line/avatar/direction/timing programs, controlled reveal rasters and directed
  browser scroll geometry. These probes do not qualify source transcript padding,
  typography, full portrait/backplate composition or complete settlement layout.
  `node tools/dialogue_layout_capture.mjs` retains all authored base-settlement
  transcripts in both art modes at 360/720/721/1440 px widths, actual downloaded
  Noto font usage, pinned external font response hashes and original image bytes.
  `tests/dialogue_layout.test.mjs` verifies complete scenario coverage, source
  identity and sealed PNG crops using their exact fractional bounding rectangles.
  Retain CSS weight selection even when the font's internal family name contains
  `Thin`. Source references populate only `overTalk` in the original
  overlay markup over a declared constant backdrop; winner/statistics content,
  touch-device classes, native typography and full settlement acceptance remain
  unresolved. Preserve the native inner script scroller and absolute background
  portrait slots; portraits must not contribute an in-flow row or intrinsic height.
  `node tools/dialogue_body_capture.mjs` retains original CSS boxes with declared
  minimum-height rows and visible browser scrollbars. `tests/dialogue_body.tscn`
  checks the inner padding/gaps, reserved scrollbar width, viewport cap, responsive
  portrait geometry and viewport reattachment. The visible scrolling box retains
  fractional source layout units independently of Godot's rounded VBox allocation.
  These probes do not qualify header baselines, actual font wrapping, outer
  settlement spacing, rounded portrait clipping, gradient mattes or scrollbar
  pixels. Keep the shared font/material gates below before full composition.
  `node tools/dialogue_fonts_capture.mjs` extends the frozen font responses to
  every original radio/settlement character, preserving `zh-Hant` Canvas language
  selection. `tools/import_dialogue_fonts.tscn` atomically publishes the original
  WOFF2 bytes as a native Theme with separate 400/700 variation/fallback graphs,
  explicit glyph coverage and an embedded original licence. It rejects changed
  input hashes, missing subsets and silent system fallback. Run
  `tests/dialogue_fonts.tscn` for reload/identity/coverage and
  `tests/dialogue_font_metrics.tscn` for the separate strict browser-advance gate.
  Keep its current precision failures visible; resource publication does not
  qualify native typography or source line wrapping. Bind the Theme only after
  the shared advance contract below is accepted for the relevant text consumer.
- [ ] **S21 — Remaining quality consumers:** finish curated visual-style
  propagation, render-resolution scaling, world-text rebuilds and remaining
  low-power effect/audio consumers. Verify source constructor versus live-update
  boundaries, persistence and whole-scene rendering. Shared main-scene/renderer
  wiring and shader changes require exact Opus handoffs.
  `node tools/visual_preferences_capture.mjs` and
  `tests/visual_preferences.tscn` retain source preference transactions, native
  ConfigFile reload and scalar marine uniform/reflection contracts. Preserve
  initialized shader-default baselines when testing material isolation; lazy
  real-driver compilation is not a material mutation. These checks do not
  establish whole-water pixels, signage rebuilds or dynamic resolution behavior.
  World captures retain per-mesh `sourceWorldText` constructor profiles, accepted
  copies/styles, atlas size, admission/drop counts and exact vertex glow. Native
  mesh resources retain the matching `source_world_text` metadata and existing
  `source_cel_geometry` frame; prefab sign-item coordinates remain local to that
  frame. Language/profile reconstruction remains unavailable until source
  candidate selection and font/atlas behavior are implemented. Do not substitute
  generic Label3D text, invented translations or a global atlas-quality setting.
  Run `tests/world_text_capture.test.mjs` for capture/storage contracts and
  real-driver `tests/world_text_import.tscn -- --non-glowing` for native reload.
  The default scene is an explicit unsupported-glow rejection (expected exit 1).

## Integration and handoffs

Run the current component references, real-driver resource/render checks and
root runtime gates for the affected behavior. Inspect existing transport case
switches for `-Loading`, `-Mobile`, `-Controls`, `-View`, `-Tps`, `-Pips`,
`-Minimap`, `-Projectiles`, `-Deaths` and `-Blasts`; invoke one switch per run.
Cross-owner changes stay as exact requests in this file until their owner pulls
them. Remove completed items; no dated checkpoints or copied validation history.

### Shared-owner contract required for world publication

- **Opus — source publisher temporary ownership:**
  `tools/fixture_json.mjs::writeSourceFile` uses PID plus `Date.now()` for its
  temporary path and removes that path after a failed exclusive write, including
  `EEXIST`. Two same-process writes to one chunk within one clock tick therefore
  collide; the rejected opener deletes the first writer's temporary file.
  Isolated concurrent 8 MiB writes with a fixed clock both reject (`ENOENT` and
  `EEXIST`) and leave no publication. Give each invocation a unique temporary
  identity and remove only successfully opened files. Preserve atomic rename,
  completed-capture retention and existing retry semantics for both source-file
  and fixture-JSON writers. Acceptance: fixed-clock concurrent writes cannot
  delete another writer's staging file; rejected exclusive opens retain foreign
  bytes, and failed encodes clean up only their own incomplete output. Sol's
  serial chunk hash/reuse checks do not discharge this shared publisher contract.

### Local execution constraints

- In this worktree, source tools need
  `$env:SVS_SOURCE='C:/Users/user/Documents/app/steel_vs_swarm'`; the default
  sibling source checkout does not exist. The required/output presence inventory
  is [world-inventory.json](../../artifacts/sol/world-inventory.json). Presence
  does not establish source fingerprints, dependency integrity or native parity.
  Browser captures also need process-local `PW_CHROME` pointing to
  `C:/Users/user/AppData/Local/ms-playwright/chromium_headless_shell-1234/chrome-headless-shell-win64/chrome-headless-shell.exe`;
  the sandbox's default Playwright browser cache is empty.
- Godot 4.7.2 is available at
  `C:/Users/user/AppData/Local/Temp/steel-v-swarm-godot/Godot_v4.7.2-stable_win64_console.exe`.
  Set process-local `APPDATA` to this worktree's `build/sol-user` and
  `LOCALAPPDATA` to `build/sol-local` for isolated test preferences and caches.
- Runtime smoke and both loading transports fail on missing seasonal native
  resources; produce the selected original bundles before repeating populated
  acceptance. Root-suite failures in other owners' fixtures do not authorize
  changing their production code or shared reference registries here.
  Root and selected NPC-shot suites also reject stale consumer dependencies.
  Projectile transport timeouts and a rendered smoke timeout without `SMOKE_PASS`
  leave integrated effect delivery unqualified; isolated effect-order acceptance
  cannot discharge these gates.
  Native font/codec caches can be generated in an isolated minimal Godot project
  from identical source assets and import descriptors, then copied into the
  ignored `.godot/imported` directory. Avoid broad editor imports that rewrite
  the shared project settings. An automatic `--quit-after` exit without
  `SMOKE_PASS` is not a passing smoke test.
- `tests/world_storage.tscn` consumes the artifacts generated by
  `node --test tests/world_source.test.mjs`. Its float64 decode/disk-reload checks
  do not establish complete world geometry, rendered appearance or delivery.

### Shared-owner contracts required for world/audio acceptance

- **Opus — exact native source JSON numbers:** expose a reusable validated
  numeric-tape boundary in `scripts/source_fixture_sections.gd` before Sol
  certifies native inline world values. Its existing `load_part` honors
  `numericEncoding: f64-le`, and `_restore_numbers` already restores source words;
  avoid a second decimal parser. The public contract must accept a captured value
  tree plus native float64 bytes, preserve tree shape, reject incomplete/extra
  words and retain the fixture loader's hash/path validation. World callers
  validate their own storage paths/hashes before restoration. The original
  Chromium small sphere has 14 double-bit
  mismatches in each position/normal array after Godot JSON parsing; the large
  sphere has 928 per array on the direct JSON path, while its float64 sidecars
  remain exact. Native resource reload retains the already-decoded small-array
  differences. `artifacts/sol/source-json/report.json` records authoritative
  expected/actual bytes; for example `0000004026a681bc` becomes `ffffff3f26a681bc`.
  Sol binds the accepted contract in `tools/source_world_meshes.gd` and
  `tools/import_worlds.gd`. Acceptance: every original JSON/inline/sidecar/reloaded
  field in `tests/source_json.tscn`, signed zero and difficult finite doubles,
  without numeric retuning, decimal correction tables or tolerance widening.
- **Opus — layered-deck reference provenance:**
  `tools/world_references.mjs` executes the live original `makeDeckIndex` without
  checking the selected world's captured `source.inputs`. It can overwrite
  `collision.deckEndTolerance` and `deckProbes` using different source while
  retaining the old source fingerprint and reporting success. An isolated
  reproduction is retained in `artifacts/sol/deck-provenance-reproduction.json`;
  it never edits an actual captured bundle. Bind the deck-reference producer and
  native-import consumer to matching original biomes/extraction-helper inputs,
  and reject missing or mismatched selected bundles before publication.
  Acceptance: changed/missing source hashes and source changes during reference
  generation preserve the original bundle byte-for-byte; matching inputs retain
  original endpoint tolerance and upper/lower deck query results. This reference
  generator includes authority query semantics and remains a separate shared-owner
  change. Sol's wrapper rechecks declared world inputs before/after references;
  it cannot certify the standalone oracle or extraction-helper contract.
  Preserve signed zero when rewriting the complete bundle as well: ordinary
  `JSON.stringify(data)` erases corrected inline metadata even when the oracle
  itself leaves that data unchanged. Bind the accepted source-number publication
  helper and retain reference results plus all unrelated captured numeric bits.
  The isolated `berlin_1_winter` rewrite erases 99 captured negative zeros in
  marine matrices, water-obstacle shapes and sampler matrices. Exact field paths
  and the preserved original-manifest checksum are retained in
  `artifacts/sol/berlin-winter-reference-proof.json`. Keep the original winter
  capture unchanged; it has no accepted layered-deck references or native
  seasonal resource until this producer contract is corrected. Raw chunk/numeric
  caches still require storage verification before reuse and do not establish
  native-world availability.
- **Opus — float vertex colors:** agree the native mesh/shader attribute contract
  in `scripts/source_cel_*.gd` and `shaders/` before Sol changes
  `tools/import_worlds.gd` to bind it. Original Berlin autumn `SourceMesh_5`
  contains active vertex colors up to `1.059999942779541`; Godot `ARRAY_COLOR`
  stores that value as `1.0`. Preserve source RGB/RGBA values, including signed
  and HDR channels, without clamping or loosening the verifier. The importer
  explicitly rejects these active channels until the shared shader accepts
  lossless storage. Acceptance: regenerate `berlin_1_autumn`, pass original
  surface-color checks in `tests/worlds.tscn` and source/native pixel comparison.
  The freshly recaptured, completely storage-verified Berlin spring bundle also
  stops on mesh 5: 4,944 of its 22,537,287 RGB components exceed one. The first
  is blue at vertex 146,852 (component 440,558), with the same maximum above.
  Exact source buffer identity and surface declarations are retained in
  [world-color-inventory.json](../../artifacts/sol/world-color-inventory.json);
  the current real-driver rejection is in `build/sol-berlin-spring-import.log`.
  Require lossless native disk reload and colored/uncolored source/native pixels
  in both quality modes before Sol binds the accepted storage contract.
- **Opus — cel resource metadata:** resolve the source/native material-table
  mismatch through `scripts/source_cel_data.gd` or its serialized consumer
  contract. Acceptance: `SourceCelData.material_source(material)` equals the
  captured per-surface `cel` declaration after native resource reload;
  `tests/worlds.tscn -- --bundle=berlin_1_autumn` must retain its exact material
  checks. Passing isolated material metadata probes does not qualify full worlds.
- Keep rejected candidates outside normal world selection, for example under
  `artifacts/sol/unqualified-worlds/`. The current worktree has no qualified
  seasonal native bundle. Prebuild transfer/lifecycle checks cannot discharge
  failed geometry/material qualification or establish absent candidate resources.
- **Opus — shared audio fixtures:** refresh the existing audio routing/state
  fields in `data/fixtures.json` through `tools/import_source.mjs` and
  `tools/model_references.mjs`. In particular, `tests/audio_suite.gd` still needs
  the source `audioEvents`/`audioPan` fields before it reaches its routing,
  preference and lifecycle checks. Preserve the producers in
  `tools/audio_references.mjs` and `tools/audio_pan_capture.mjs`; do not invent
  outputs or relax the entry guard. The independent native resource/mixer scenes
  use Sol-owned captures and cannot certify the missing shared decision fixtures.
  The shared gate/count/sample sections still declare producer input
  `tools/audio_references.mjs` as
  `d1a87b6357256bf6059f017f3eee3f2bea8e4f6ccf74b445402d0b35cec084d1`,
  while the current normalized module is
  `3de024594ab66b555c6df2e54a2def16c957981acd4bd5c2666aaabc278df245`.
  Refresh those shared producer declarations through the importer; Sol's separate
  manager capture reuses the current recorder without editing this registry.
- **Opus — shared audio provenance/consumer publication:** refresh
  `data/provenance.json` and the shared fixture consumer manifests through
  `tools/import_source.mjs`. Original `public/js/rng.js` and Sol's
  `data/audio_lifecycle.json` agree on SHA-256
  `96773f680724e2fc8e695270333d41d3a18e539dabb88968dad0b9cb68fae654`, while
  runtime provenance still declares
  `c46913b415a75aa5f0d2366dd7bfcb4f8f26c1db913ecea2a74b40695dd78aaa`.
  The lifecycle generator correctly refuses to overwrite this mismatch. Refresh
  dependency declarations for `tests/audio_clip_suite.gd` and
  `tests/audio_move_suite.gd` after their catalogue-based resource binding; preserve
  the original expected samples, control programs and strict fingerprint guards.
  Acceptance: `tests/audio_lifecycle.tscn` reaches its original programs without
  bypassing provenance, and the root suite accepts the current audio consumers.

### Shared-owner contracts required for local feedback

- **Opus — browser pulse sine:** provide an accepted shared binding in
  `scripts/source_trigonometry.gd` for original browser `Math.sin` before Sol
  certifies bit-identical lock-glow scalar states. `tests/fixtures/lock_glow.json`
  retains original Node and Chromium constructor/callback outputs, runtime
  identities, pulse inputs and sine bits. Current native phase bits agree, but
  the native sine differs at large inputs and changes 249 halo-size/opacity and
  ring-scale double results; the strict scene deliberately remains failing.
  `artifacts/sol/lock-glow-differences.json` records each input and both sine
  bit patterns. The sampled native Float32 outputs and ring orientations agree;
  those checks cannot establish scalar parity. Acceptance: all captured scalar
  bits and additional argument-reduction boundaries agree with the original
  Chromium execution, without baked input tables, angle wrapping or tolerance
  changes. Node and Chromium sine bits also differ in part of this corpus;
  Node-only capture is insufficient to choose the shared browser binding.

- **Opus — spectator angle transfer:** `scripts/main.gd::_advance_spectator`
  packs double `yaw`/`pitch` into `Vector2` before calling
  `SpectatorCamera.advance`, then unpacks its Float32 `Vector2` result. Agree a
  double-preserving producer/consumer contract with Sol before changing the
  camera API; the native pose writer cannot recover precision already discarded
  by this boundary. Preserve the source unbounded yaw and input increments, not
  a wrapped/canonicalized Euler substitute. Acceptance: repeated sub-Float32
  input increments at a large fractional yaw retain original free/orbit camera
  motion and orientation, plus existing FPV/TPS follow, zoom, reset and lifecycle
  behavior. Authority heading and gameplay settlement remain unchanged.
- **Opus — snapshot acceptance before feedback:** `scripts/session.gd::_snapshot`
  emits `state_received` even when `scripts/simulation.gd::apply_snapshot`
  rejects an older clock. `scripts/main.gd::_receive_state` then consumes the
  rejected control publication, optimistic cast state and presentation clock.
  Give the producer/consumer one round-scoped acceptance contract before those
  mutations. Acceptance: after newer freeze/EMP/cast/control edges, an older
  snapshot and duplicate snapshot cannot rewind state or rearm notices; later
  valid false/true edges still notify, and a new round accepts its initial clock.
  Preserve separately delivered tactical events and offline authority snapshots;
  component-local projectile guards cannot discharge this shared integration.
- **Opus — owner unbalance notice:** `scripts/actor_snapshot.gd` currently
  publishes `unbalLeft` but omits the `unbalanced` field consumed by
  `ControlStatusState` through `scripts/main.gd`. Publish an explicit owner-only
  boolean using actual flying/dead/drone/altitude/wind/sink/lift-lock state from
  `scripts/simulation.gd`, following the original client `_unbalanced()`.
  Use recipient-rounded `unbalLeft` for the status branch, not the raw authority
  deadline remainder. Existing `MovementRules.flight_unbalanced()` provides the
  predicate once given that recipient state. Acceptance: grounded/dead and
  below-threshold drones publish false; airborne sinking/lift-lock/status each
  independently publish true; exact altitude/lock and rounded-zero status
  boundaries retain source behavior. Repeated true snapshots emit one notice,
  false then true emits another, and replayed snapshots emit none. Do not infer
  this flag from `unbalLeft` alone or add client resource settlement.

### Shared-owner contracts required for projectile acceptance

- **Opus — original presentation pool provenance:** refresh `data/provenance.json`
  through `tools/import_source.mjs` before Sol captures original `_initFxPools`,
  `_releaseFxLine` and `Pool.release` together. Current original
  `public/js/pool.js` hashes to
  `58b938ad46b8c4afd0036612f143a4bdb52be72af6b9d45eb73ae229a690b84b`,
  while imported metadata declares
  `5040958ee9974e92e7cf25ad784bb92b0c76f02a6f8d9de60baa13b1cd5b987e`.
  The guard must reject this mixed identity; do not reuse an invented Pool or
  relax the fingerprint check. Acceptance: original prewarm, bounded LIFO release,
  overflow disposal and reentrant shell retirement execute against one accepted
  source snapshot. Sol's current supplied-line probes certify vertex/fade writes,
  not the absent pool qualification. The exact identities are retained in
  [tracer-pool-source.json](../../artifacts/sol/tracer-pool-source.json).
- **Opus — shared projectile fixture publication:** refresh `data/fixtures.json`
  through `tools/import_source.mjs` before full projectile acceptance. The shared
  `visualShells`, `projectileGeometry` and `tracerPresentation` sections declare
  `tools/projectile_references.mjs` as
  `44d833f86189b5e8a394249b3b7c4988144bb3093a2cc6014d9ea73602af2cd0`,
  while the current normalized producer is
  `9a8545ae29e9c1a51ab5fed6d35050028cbe78ff767a2125f24a8d5169c3ca35`.
  Preserve original flight, geometry, material and tracer expectations and the
  source fingerprint guards. Acceptance: the shared projectile suites consume
  current producers/consumers without substituting Sol's narrower ownership oracle.

### Shared-owner contracts required for particle acceptance

- **Opus — current particle provenance:** reconcile the original source inputs
  through `tools/import_source.mjs` and `data/provenance.json` before publishing
  another `tests/fixtures/destruction.json`. Its current capture disagrees with
  shared provenance for `public/js/rng.js`, `public/js/pool.js`,
  `public/js/lookPrefs.js` and `public/js/movePrefs.js`. Keep all four source
  guards and the strict particle comparisons. Acceptance: regenerate from the
  agreed original inputs, then execute both particle families on the real driver;
  a compiling fixture adapter does not qualify debris, comics or imported pixels.
- **Opus — debris source random contract:** the original default
  `vfx.debrisBurst()` path captured by `tools/destruction_references.mjs` consumes
  `Math.random` while constructing Three.js groups/materials/instance batches,
  before sampling chunk parameters. The first normal/small case consumes 73
  draws versus native `MechanicalDebris`'s 49, shifting the first scale from
  source `0.5774999856948853` to native `0.498750001192093` and later motion.
  Publish source-derived allocation/effect draw separation for Sol to consume;
  do not insert unexplained constant RNG burns or silently shift expected data.
  Preserve the distinct explicitly injected random callback used by seeded
  scenery bursts. Acceptance: all default and seeded cases retain their original
  parameters, draw order, bounce/spin/shrink and independent combat RNG streams.
- **Opus — lossless debris palette binding:** agree the shared cel shader
  contract in `shaders/` and `scripts/source_cel_*.gd` before Sol changes the
  `MechanicalDebris` MultiMesh binding. Current per-instance colors round source
  float32 `0.0930589661002159` to `0.093017578125` on the real OpenGL driver.
  Palette indices are exactly representable, but the accepted shader must resolve
  them to the original float32 palette/accent without half-float color loss.
  Keep original low-power two-batch/full-power four-batch topology and metal
  shading. Acceptance: strict matrix/color checks in `tests/destruction_native.tscn`
  and source/native pixels, including accent zero and both quality modes.
- **Opus — comic PNG import contract:** `tools/import_source.mjs` publishes
  `assets/ui/combat-comic-*.png` without source-preserving texture import settings.
  All 32 captured PNGs match original decoded pixels, while all 32 imported
  textures differ with `process/fix_alpha_border=true`. The first texture has
  6,506 changed transparent and 174 changed nonzero-alpha pixels; applying
  `Image.fix_alpha_edges()` to its original pixels reproduces the imported bytes
  exactly. Publish the
  explicit import configuration and reimport through the shared pipeline;
  leave original PNGs immutable. Acceptance: original captured RGBA bytes equal
  the imported `Texture2D.get_image()` bytes, then qualify native billboard pixels.
  Passing sprite scale/opacity/roll/pool state does not discharge this texture gate.

### Shared-owner contracts required for death presentation

- **Opus — source CSS inset-shadow raster:** fix the accepted shader contract in
  `shaders/death_rim_mask.gdshader`, `shaders/death_rim_present.gdshader` and the
  shared `shaders/splat_blur.gdshader` before Sol changes their viewport bindings.
  Current original CSS/native comparisons fail the rim cases at 640x360,
  360x640 and 128x128, with 44,308 / 53,001 / 5,837 mismatched pixels and maximum
  premultiplied-channel errors 0.027451 / 0.027451 / 0.023852. Whiteout cases
  pass at the existing tolerance. Acceptance: all six original raster cases in
  `tests/death_render.tscn -- --source-capture` pass without loosening
  `tests/raster_compare.gd`; retain source inset spread, blur, corner coverage and
  transparent composition. Diagnostics are in `build/death_render/`.
- **Opus — shared death integration fixture cleanup:**
  `tests/death_sequence_suite.gd::run` stores a lambda on each RefCounted sequence
  that captures the same sequence strongly. Clear its callbacks after each case
  or use an explicitly typed `WeakRef`; retain its `_lifecycle` assertions against
  `scripts/main.gd` and `scripts/unit.gd`. Acceptance: source sequence checks and
  camera ownership/early respawn/reset integration pass with no ObjectDB/resource
  leaks or engine errors at exit. Sol's source-only `tests/death_native.tscn`
  avoids that cycle but does not certify the omitted shared lifecycle checks.

### Shared-owner contracts required for loot frame integration

- **Opus — capped/hitstop frame delivery:** `scripts/main.gd::_process` obtains
  the accepted delta from `PresentationFrame.advance`, while the independently
  processing loot/airdrop nodes receive raw engine deltas. Original
  `BattleClient` passes its single adjusted `dt` to `_updateLoot` and
  `_updateAirdrop`, alongside continuous local wall time. Agree one main-to-world
  frame contract so Sol can expose the matching consumers without double-stepping
  or introducing another hitstop budget. Acceptance: long stalls retain the
  source delta cap; hitstop freezes spin but wall-clock bob/descent phases retain
  original behavior; snapshot bursts never restart either clock. Keep authority
  simulation time and resource settlement unchanged.
- **Opus — native loot orientation assertions:** when refreshing shared
  `lootVisuals` / `airdropVisuals`, update `tests/scene_suite.gd` and
  `tests/supply_suite.gd` to distinguish source double phase from the native
  quaternion pose. Node3D canonicalizes Euler representations after quaternion
  writes, so raw Euler-vector equality is not a valid pose comparison across
  complete turns. Preserve source phase/delta bits as demonstrated by
  `tools/loot_clock_capture.mjs`; assert the double phase on presentation state
  and source quaternion orientation on the actual node. Acceptance includes
  both short original programs and fractional large-angle states without
  increasing pose tolerances or changing authority behavior.

### Shared-owner contracts required for campaign art

- **Flash — settlement transcript host:** `scripts/campaign_ui.gd::show_result`
  owns the outer expandable transcript ScrollContainer and the result
  title/statistics/buttons. Bind the source settlement host width, outer overflow
  and placement around `CampaignDialogue.transcript()` without expanding the
  inner script beyond its original 42vh cap or counting background portraits in
  text flow. Sol's visible inner box preserves fractional CSS height; native VBox
  allocation alone does not establish source outer spacing. Acceptance: complete
  populated victory/defeat and replay layouts at 360/720/721/1440 px widths after
  the accepted font/material bindings, including nested nearest scrolling.
  `tests/fixtures/dialogue_layout.json` populates only original `overTalk`; its
  crops cannot certify the missing winner/statistics and outer-host content.
- **Opus — source text advances:** provide an accepted shared adapter in
  `scripts/source_font_metrics.gd` before Sol certifies source dialogue wrapping.
  Input is the published native Font, original text, pixel size and `zh-Hant`
  language; preserve original shaping/kerning and the captured CSS weight.
  The strict browser widths are in `tests/fixtures/dialogue_fonts.json`, and
  native public widths plus unrounded glyph sums are retained in
  `build/dialogue_fonts/metrics-report.json`. Native integer widths are not the
  same contract as browser fractional advances; disabling hinting/rounding or
  using native MSDF did not establish parity. Acceptance needs the complete
  source corpus, Latin/CJK/punctuation, both weights and all recorded sizes,
  without arbitrary spacing corrections, tolerance widening or a baked table of
  whole-string widths. Sol owns subsequent Label/row layout and pixel binding.
- **Opus — transcript portrait matte and avatar frames:** agree accepted native
  bindings under `shaders/` for original `.dlg-art` and `.dlg-av` pixels before
  full transcript composition is accepted. Background portraits retain 150 px
  width, bottom alignment, whole-image opacity 0.22, right-side mirroring and
  `linear-gradient(to top, #000 30%, transparent)` alpha masking; the body clips
  them at its 8 px rounded boundary. Avatar frames retain the SWARM 16%/84%
  polygon, STEEL 2 px radius plus its 1 px outline at 2 px offset, and MERC
  3 px double border/6 px radius. Preserve original RGBA and premultiplied group
  composition without mutating imported textures. Source computed styles and
  populated pixels are in `tests/fixtures/dialogue_layout.json`; acceptance
  needs isolated material probes in both art modes, alpha-gradient endpoints,
  fractional placement and the complete native/source transcript composition
  after Sol publishes the captured fonts and container geometry.
- **Opus — radio portrait filter binding:** agree an isolated canvas-item shader
  contract under `shaders/` for the original `.dlg-row .dlg-av` grayscale filter.
  Source inactive portraits use opacity 0.35 and grayscale 0.75; `.on` uses opacity
  1 and no filter, with both channels transitioning for 0.18s ease-out. Native
  `CampaignDialogue` currently uses instantaneous alpha 0.5/1 and no grayscale.
  Preserve original portrait pixels/alpha and shared texture immutability; Sol
  binds the accepted material and complete transitions in a separate change.
  Acceptance: original CSS/native portraits at both endpoints, transition and
  reversal frames, across character/mech modes and guest/single-speaker cases.
  Passing state/asset-path checks in `tests/dialogue_native.tscn` cannot certify
  opacity, grayscale, faction frames or complete dialogue pixels.
- **Opus — story image encoding:** `tools/import_source.mjs` copies original
  story images verbatim under their original `.png` names, but all 70 PNG-named
  files in `assets/story/` contain JPEG JFIF bytes (`FF D8 FF E0`), and all 70
  have invalid native imports. The complete presence/encoding inventory is in
  `artifacts/sol/campaign-art-inventory.json`.
  Publish correctly encoded native PNGs through the shared importer while
  preserving immutable original source files and campaign path metadata; do not
  hand-edit image data or `.import` validity flags. Acceptance: every campaign
  art path loads normally and with mipmaps, fallback selection follows original
  semantics, and native art pixels match the original decoded images.
- **Opus — failed story load guard:** `scripts/content.gd::story_texture`
  calls `get_image()` without checking whether `load()` returned a texture when
  mipmaps are requested. Reject a failed native decode before dereferencing it,
  preserving the original fallback contract and explicit availability checks.
  Acceptance: invalid imports never crash mipmap generation; valid foreground,
  background and portrait paths remain reusable without corrupting cached art.

### Shared-owner contracts required for renderer quality

- **Opus — cinematic hold stroke coverage:** agree an accepted material in
  `shaders/cinematic_hold.gdshader` before Sol replaces the native SVG binding in
  `scripts/campaign_hold.gd`. Godot's native SVG raster retains the original
  geometry, dash targets and rounded caps but differs from browser coverage in
  the quarter/half/full and translucent-half progress cases by 104/199/372/165
  pixels at the unchanged two-byte threshold (maximum normalized errors
  0.187912/0.286275/0.243460/0.097732). Static backplate, translucent group and
  cancelled-dash controls pass. Keep the captured radius, width, color, dash
  array, source analytic circumference and distinct browser path length;
  cancellation must not leave a spurious rounded-cap dot. Acceptance: all seven
  original CSS/SVG cases in `tests/campaign_hold_render.tscn` and continuous
  progress/reversal frames, without width/color retuning, a finite baked-progress
  substitute or a looser raster tolerance. Source/native evidence is retained in
  `build/campaign_hold/`; Sol binds the accepted shared renderer in a separate change.
- **Opus — minimap mask raster contract:** agree source-faithful scratch-mask
  coverage and read/composition materials in `shaders/minimap_*.gdshader` before
  Sol changes the `MinimapMaskTile`/`MinimapFog` bindings. Native `draw_ellipse`
  and antialiased Polygon2D masks retain the source geometry but do not yet match
  original Canvas coverage and persistent source-over accumulation. At the
  unchanged four-byte tolerance, full composite frames 1–4 differ in
  422/515/1,610/784 pixels; exploration frames 1–5 differ in
  456/566/542/842/842 pixels, with maximum alpha difference 220/255. Direct alpha
  witnesses in `build/minimap_fog/report.json` confirm real coverage differences,
  independently of RGB premultiplication. Existing point probes still pass.
  Preserve per-source shadow clipping, hard/soft order, full-map exploration,
  vicinity resampling, pulse fill, observer bypass and reset. Acceptance: all
  twenty source/native raster comparisons from the ten-frame sequence in
  `tests/minimap_fog_render.tscn -- --source-capture --full-raster`, without
  widening tolerances or replacing persistent masks with a generic reveal.
- **Opus — original aquatic point compositing:** qualify
  `shaders/aquatic_points.gdshader` against original Three.js PointsMaterial
  color/opacity composition, retaining vertex colors, depth, perspective size
  attenuation and pixel-ratio behavior. All six original cases in
  `tests/aquatic_render.tscn -- --source-capture` currently fail at the unchanged
  two-byte tolerance: 392/32/120/6/392/8 pixels, each with maximum channel error
  44/255. Source/native images are in `build/aquatic_render/`; the capture uses
  original material construction and source colors, not invented palette values.
  Acceptance: all six source rasters and native motion/buffer isolation checks,
  with no source-color retuning or tolerance increase. Point-state equivalence
  does not qualify point colors, transparency or complete water composition.
- **Opus — source scope ring color:** `tools/view_references.mjs` currently
  selects `rgba(ringCss)[0]`, the transparent center stop, as `mask.ringColor`.
  Consequently `data/balance.json` contains `[0,0,0,0]`, and the native scope
  has no visible ring. Select the original visible ring stop and verify its
  repeated declarations agree before publishing through `tools/import_source.mjs`.
  Original CSS uses `rgba(150,200,230,0.4)` for the two-pixel ring; do not patch
  imported data or hardcode a replacement in `ScopeOverlay`. Acceptance: native
  source-config equality and the scoped-clear cases in `tests/scope_raster.tscn`,
  followed by full ordered fog composition at all three viewport sizes.
- **Opus — source scope backdrop composition:** finish `shaders/scope_mask.gdshader`
  against the original CSS Gaussian backdrop filter and layer/group ordering.
  Source scope mask/ring is z7, then the fire element's backdrop blur and gradient
  share its opacity at z8, followed by weather fog. Native mip-level sampling and
  successive opacity mixes are not a qualification of that composition. The
  unscoped 0.8-fire cases differ in 202,944 / 202,976 / 11,692 pixels at 640x360,
  360x640 and 128x128, with maxima 15 / 15 / 25 channel bytes. Preserve the source
  blur amount and scope-edge coverage; do not loosen the existing tolerance.
  Acceptance: original `tests/scope_raster.tscn` cases, including mixed fire/weather
  and high-density small scoped views, after the ring-color producer is corrected.
- **Opus — raster comparator byte boundary:** `tests/raster_compare.gd` compares
  Color's Float32-normalized channel differences against double `2.0/255`.
  Opaque weather-only cases 2/8/14 in `build/scope_raster/report.json` have exact
  RGB8/RGBA8 differences no greater than two bytes, yet report 107/102/8 failed
  pixels because the normalized difference reaches `0.00784316658973694`.
  Preserve the two-byte tolerance and transparent premultiplied semantics while
  making the boundary numerically faithful. Acceptance includes exact 0/1/2/3
  byte differences, opaque and transparent buffers, and the source/native raster
  suites; Sol's witness records do not suppress the current strict failures.
  Also retain frame 7 of `tests/campaign_art.tscn`: every opaque channel differs
  by at most two bytes, yet the current normalized comparator reports 2,240
  pixels at `0.0078431386500597`. `build/campaign_art/report.json` records zero
  pixels over two bytes; the other twelve first-frame scene comparisons pass.
- **Opus — source resolution governor integration:** `scripts/main.gd` currently
  reads `get_viewport().scaling_3d_scale` for PiP but never applies the original
  `_dpr` / `_applyRes` / `_tickResGov` renderer contract. Agree the native DPI,
  frame/load metrics and visibility inputs through `scripts/main.gd`,
  `scenes/main.tscn` and `project.godot` before exposing render-scale behavior.
  Preserve source low-power DPR 1, touch DPR cap 1.5, desktop cap 2 and desktop
  dynamic scale 1; the touch governor retains spike/hidden-frame exclusion,
  complexity weighting, recovery cooldown and permanent reversal shutdown.
  Acceptance: source-oracle frame programs, actual viewport dimensions and PiP
  scaling agree across low-power changes, resize and visibility transitions.
  Do not substitute a fixed low-resolution toggle for the source governor.
- **Opus — original sign emission:** agree a lossless per-vertex `signGlow`
  binding in `scripts/source_cel_*.gd` and `shaders/`, using captured
  `sourceWorldText.glow` and the original text atlas. Original
  `worldtext.js::applySignGlow` multiplies atlas-sampled emissive radiance by the
  interpolated vertex attribute, so unlit civic plates and backlit tactical
  plates share one mesh/material. Preserve Float32 values, single-sided front/
  back geometry, source UV inset and atlas sampling; do not apply one emission
  amount to every plate. Acceptance: mixed zero/nonzero source glow and lit/unlit
  raster fixtures match before Sol enables the native import path. The importer
  currently rejects active glow instead of silently dropping the attribute.

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
  Keep compressed-candidate and existing-sidecar hashing streamed; never buffer
  a complete numeric sidecar just to determine its size or verify its digest.
  Existing Berlin spring/summer/autumn resources are partial inputs, not world-set
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
- [ ] **S5 — Environment appearance:** finish cloud/fog-bank detail,
  precipitation, celestial bodies, deposits/scorch, contact effects,
  shoreline/underwater/waves/reflections and
  source wind/wave/gust/tide/ripple/vessel coupling. Bind the shared shader owner's
  accepted materials; certify weather style/low-power transitions and full
  seasonal rendered composition. Weather damage and hazards remain authority-owned.
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
  Held build signals exercise retirement without qualifying seasonal geometry.

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
  composition gate. Run `tests/campaign_hold_render.tscn` for the seven original
  pixel cases;
  static/group controls pass but dynamic native SVG stroke coverage remains an
  open shared-renderer contract below. Do not certify full cinematic pixels,
  fractional/DPI placement, hardware input, export or performance from these probes.
  Finish original first-play asset readiness, buffer-warning presentation and
  skip-readiness gates before accepting the complete loading/cinematic lifecycle.
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
  unresolved. Implement native inner script scrolling/padding and absolute
  background art without turning the portraits into an in-flow row.
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

## Integration and handoffs

Run the current component references, real-driver resource/render checks and
root runtime gates for the affected behavior. Inspect existing transport case
switches for `-Loading`, `-Mobile`, `-Controls`, `-View`, `-Tps`, `-Pips`,
`-Minimap`, `-Projectiles`, `-Deaths` and `-Blasts`; invoke one switch per run.
Cross-owner changes stay as exact requests in this file until their owner pulls
them. Remove completed items; no dated checkpoints or copied validation history.

### Shared-owner contracts required for campaign art

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


### Shared-owner contracts required for cinematic renderer quality

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
- **Opus — raster comparator byte boundary:** preserve the two-byte budget in
  `tests/raster_compare.gd` while comparing opaque RGB8 channels numerically.
  Frame 7 of `tests/campaign_art.tscn` differs by at most two channel bytes,
  with zero pixels over that limit, but the normalized Float32 comparison
  reports 2,240 pixels at `0.0078431386500597`. Keep the strict failure and
  witness in `build/campaign_art/report.json`; the other twelve first-frame
  scene comparisons pass. Acceptance includes exact 0/1/2/3-byte differences,
  transparent premultiplied buffers and the unchanged source/native suites.

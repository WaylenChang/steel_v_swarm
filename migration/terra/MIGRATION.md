# Bounded visual consumers — outstanding work

Read [AGENTS.md](AGENTS.md). The root router assigns S12-S14 and S20 to Terra;
IDs and existing evidence paths are retained. Work one bounded fixture-backed
change at a time. These acceptance inventories do not authorize a whole-system
rewrite or edits to producer APIs. Complex work may use Sol 6.1 in this lane.

## View, scope, minimap and PiP

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

## Campaign presentation

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
  Dialogue detachment cancels pending radio/transcript deadlines and native
  animations; reattachment requires fresh playback. Seal old radio references
  before visibility callbacks, and cancel superseded construction or clock
  continuations before admitting nodes or timers. A queued/detached transcript
  host must not reveal or scroll from a pending deadline. Preserve replacement
  state during clear/dispose/expiry callbacks and release unadmitted portraits.
  `node tools/dialogue_owner_capture.mjs` executes original `_after`, `clear`
  and `dispose` with declared timer/DOM probes; real-driver
  `tests/dialogue_owner_retirement.tscn` checks these programs and native
  admission, reentrancy, paused detachment and retained-owner resource release.
  This scoped cancellation oracle does not qualify the full original dialogue
  dependency graph, layout, art/filter pixels or populated campaign delivery.
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

## Integration and handoffs

- **Opus — browser pulse sine:** provide an accepted shared binding in
  `scripts/source_trigonometry.gd` for original browser `Math.sin` before Terra
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
  double-preserving producer/consumer contract with Terra before changing the
  camera API; the native pose writer cannot recover precision already discarded
  by this boundary. Preserve the source unbounded yaw and input increments, not
  a wrapped/canonicalized Euler substitute. Acceptance: repeated sub-Float32
  input increments at a large fractional yaw retain original free/orbit camera
  motion and orientation, plus existing FPV/TPS follow, zoom, reset and lifecycle
  behavior. Authority heading and gameplay settlement remain unchanged.
### Shared-owner contracts required for campaign art

- **Opus — automatic dialogue/transcript provenance:** reconcile the original
  `public/js/rng.js` dependency through `tools/import_source.mjs` and
  `data/provenance.json` before full dialogue qualification. Both
  `tests/fixtures/dialogue_native.json` and `tests/fixtures/dialogue_transcript.json`
  declare `96773f680724e2fc8e695270333d41d3a18e539dabb88968dad0b9cb68fae654`,
  while shared provenance declares
  `c46913b415a75aa5f0d2366dd7bfcb4f8f26c1db913ecea2a74b40695dd78aaa`.
  Preserve the full captures and their source guards. Acceptance: original
  automatic radio and transcript programs pass with the agreed complete source
  inputs and unchanged timing/asset comparisons; the narrower cancellation
  oracle cannot substitute for these checks or certify populated delivery.
- **Flash — settlement transcript host:** `scripts/campaign_ui.gd::show_result`
  owns the outer expandable transcript ScrollContainer and the result
  title/statistics/buttons. Bind the source settlement host width, outer overflow
  and placement around `CampaignDialogue.transcript()` without expanding the
  inner script beyond its original 42vh cap or counting background portraits in
  text flow. Terra's visible inner box preserves fractional CSS height; native VBox
  allocation alone does not establish source outer spacing. Acceptance: complete
  populated victory/defeat and replay layouts at 360/720/721/1440 px widths after
  the accepted font/material bindings, including nested nearest scrolling.
  `tests/fixtures/dialogue_layout.json` populates only original `overTalk`; its
  crops cannot certify the missing winner/statistics and outer-host content.
- **Opus — source text advances:** provide an accepted shared adapter in
  `scripts/source_font_metrics.gd` before Terra certifies source dialogue wrapping.
  Input is the published native Font, original text, pixel size and `zh-Hant`
  language; preserve original shaping/kerning and the captured CSS weight.
  The strict browser widths are in `tests/fixtures/dialogue_fonts.json`, and
  native public widths plus unrounded glyph sums are retained in
  `build/dialogue_fonts/metrics-report.json`. Native integer widths are not the
  same contract as browser fractional advances; disabling hinting/rounding or
  using native MSDF did not establish parity. Acceptance needs the complete
  source corpus, Latin/CJK/punctuation, both weights and all recorded sizes,
  without arbitrary spacing corrections, tolerance widening or a baked table of
  whole-string widths. Terra owns subsequent Label/row layout and pixel binding.
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
  after Terra publishes the captured fonts and container geometry.
- **Opus — radio portrait filter binding:** agree an isolated canvas-item shader
  contract under `shaders/` for the original `.dlg-row .dlg-av` grayscale filter.
  Source inactive portraits use opacity 0.35 and grayscale 0.75; `.on` uses opacity
  1 and no filter, with both channels transitioning for 0.18s ease-out. Native
  `CampaignDialogue` currently uses instantaneous alpha 0.5/1 and no grayscale.
  Preserve original portrait pixels/alpha and shared texture immutability; Terra
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

### Shared renderer contracts

- **Opus — cinematic hold stroke coverage:** agree an accepted material in
  `shaders/cinematic_hold.gdshader` before Terra replaces the native SVG binding in
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
  `build/campaign_hold/`; Terra binds the accepted shared renderer in a separate change.
- **Opus — minimap mask raster contract:** agree source-faithful scratch-mask
  coverage and read/composition materials in `shaders/minimap_*.gdshader` before
  Terra changes the `MinimapMaskTile`/`MinimapFog` bindings. Native `draw_ellipse`
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
  suites; Terra's witness records do not suppress the current strict failures.
  Also retain frame 7 of `tests/campaign_art.tscn`: every opaque channel differs
  by at most two bytes, yet the current normalized comparator reports 2,240
  pixels at `0.0078431386500597`. `build/campaign_art/report.json` records zero
  pixels over two bytes; the other twelve first-frame scene comparisons pass.

### Execution and producer boundaries

- Read only the selected task's source, fixture generator and acceptance commands.
  Run the root suite, smoke and relevant `-View`, `-Tps`, `-Pips` or `-Minimap`
  transport case after runtime edits, one switch per run. Campaign changes add
  lifecycle and real-driver composition checks. Passing component probes never
  establish populated delivery or complete pixels.
- Use process-local `APPDATA=build/terra-user` and
  `LOCALAPPDATA=build/terra-local`; new reports belong in `artifacts/terra/`.
  Existing `artifacts/sol/` and `build/` evidence is retained at its original path.
  Fixed-output captures, native imports and shared publishers run serially.
  Source tools here require process-local
  `SVS_SOURCE=C:/Users/user/Documents/app/steel_vs_swarm`; browser captures require
  `PW_CHROME=C:/Users/user/AppData/Local/ms-playwright/chromium-1234/chrome-win64/chrome.exe`.
  Godot is at
  `C:/Users/user/AppData/Local/Temp/steel-v-swarm-godot/Godot_v4.7.2-stable_win64_console.exe`.
  Missing native worlds still block populated runtime/transport acceptance.
- **Sol — CSS/input/frame dependencies:** consume `scripts/css_transition.gd`,
  `scripts/css_decimal.gd`, local input/feedback and world/resource producers
  through their existing APIs. Record a local request before changing a payload,
  wall/game clock, cancellation or resource-ownership contract. Acceptance must
  include affected view and campaign source fixtures and lifecycle cases.
- **Sol — S21 quality propagation:** Terra owns quality bindings inside its
  allowlisted consumers. Sol retains `scripts/visual_preferences.gd` and S21
  world/audio/effect propagation. Any changed notification or constructor/live
  boundary requires an agreed producer contract and source preference plus
  affected scope/minimap/PiP/campaign regression cases before consumer wiring.

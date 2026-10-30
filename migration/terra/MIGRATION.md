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
  cancellation. Both fog transitions use wall time even when the game is paused
  or runs at a different speed. Native tween writes must reach shader uniforms in
  the same frame.
  `node tools/scope_transition_capture.mjs` and real-driver
  `tests/scope_transition.tscn` compare original browser transitions and native
  uniforms and test paused, zero-speed and accelerated wall-clock transitions;
  these checks do not certify scope gradient/blur pixels or complete
  frame-order, freeze/death and populated view integration.
  Removing the overlay or an ancestor cancels both fog tweens and settles their
  retained targets, so reattachment cannot revive pre-detachment motion.
  `node tools/scope_detach_capture.mjs`, `node --test tests/scope_detach.test.mjs`
  and real-driver `tests/scope_detach.tscn` compare both original CSS fade
  directions, fresh transitions after reattachment and paused ancestor removal.
  These lifecycle probes do not certify source backdrop or weather pixels.
  Scope radius, visible weather-gradient stops and fire blur retain the original
  double-precision CSS serialization before native vector storage.
  `node tools/scope_values_capture.mjs`, `node --test tests/scope_values.test.mjs`
  and real-driver `tests/scope_values.tscn` compare 749 original browser HUD
  cases, including decimal rounding boundaries and exact input bits, against the
  shader parameters. An unscoped weather gradient also keeps its prior stops
  while fading to zero. `tests/scope_weather_retention.tscn` retains the original
  fade and mode-change programs, including the four shared-shader failures below.
  These values do not qualify the shared shader or full pixels.
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
  Observer heading retains the previous value when a target heading is absent
  or null, and clamps nonpositive interpolation time to the original no-motion
  behavior. `node tools/spectator_heading_capture.mjs`,
  `node --test tests/spectator_heading.test.mjs` and real-driver
  `tests/spectator_heading.tscn` compare 300 original Chromium cases across
  follow modes, unbounded headings and delta boundaries. Controlled rows do not
  qualify populated snapshot delivery or complete camera rendering.
  Nearest-player selection compares squared distances in scalar doubles, in the
  source operation and stable reduction order; Vector3 squared-distance rounding
  can otherwise turn distinct candidates into a tie.
  `node tools/spectator_nearest_capture.mjs`,
  `node --test tests/spectator_nearest.test.mjs` and real-driver
  `tests/spectator_nearest.tscn` retain original selection/notice programs for
  Float32-representable positions, exact ties and non-finite comparisons. These
  controlled inputs do not recover position precision lost upstream or qualify
  populated observer delivery.
  Orbit anchor snapping compares the source double-precision distance against the
  strict threshold before interpolation; a Vector3 distance rounded to the
  threshold can otherwise smooth a target the original snaps to immediately.
  `node tools/spectator_snap_capture.mjs`,
  `node --test tests/spectator_snap.test.mjs` and real-driver
  `tests/spectator_snap.tscn` retain the original anchor branch for boundary,
  locked-view, first-anchor and moving-frame cases. These controlled positions do
  not establish upstream precision or populated observer delivery.
  Orbit anchor interpolation retains scalar doubles across frames and compares
  the unrounded anchor to the snap threshold; native Vector3 conversion occurs
  only when exposing the anchor. Resetting or assigning the anchor replaces all
  retained coordinates. `node tools/spectator_anchor_capture.mjs`,
  `node --test tests/spectator_anchor.test.mjs` and real-driver
  `tests/spectator_anchor.tscn` compare 454 original frames, including small
  motion, negative coordinates, view resets, nonpositive deltas and a snap after
  accumulated smoothing. They check double anchor, distance and coefficient bits
  as well as the exposed Float32 position. These controlled Float32 inputs do not
  recover upstream precision or qualify complete camera poses and delivery.
  FPV spectator eye coordinates preserve the source multiplication and addition
  order in scalar doubles before entering native Vector3 storage.
  `node tools/spectator_fpv_pose_capture.mjs`,
  `node --test tests/spectator_fpv_pose.test.mjs` and real-driver
  `tests/spectator_fpv_pose.tscn` compare 588 browser cases across controlled
  imported profiles, headings, native-representable positions and the flight
  threshold. These probes do not qualify upstream positions or headings, camera
  orientation matrices, populated actor rendering or delivery.
  Free spectator movement retains scalar position across frames, applies the
  original diagonal/boost operation order and clamps floor before ceiling. Mode
  changes carry the unrounded follow anchor into free movement, and nearest-player
  acquisition compares that retained position, including exact distance ties.
  `node tools/spectator_free_capture.mjs`,
  `node --test tests/spectator_free.test.mjs` and real-driver
  `tests/spectator_free.tscn` compare 312 original frames, scalar and native
  position bits, selection, resets and controlled terrain/ceiling transitions.
  World surface queries still receive native Vector3 coordinates; these controlled
  surfaces do not qualify populated terrain queries, the shared angle transfer,
  camera orientation or recipient delivery.
  Third-person follow and orbit retain scalar anchor/camera coordinates through
  the local pull calculation; native vectors are created at world-query and
  camera boundaries. Segment samples retain scalar interpolation and floor
  comparisons, while the legacy Vector3 pull callback remains supported.
  `node tools/spectator_tps_capture.mjs`,
  `node --test tests/spectator_tps.test.mjs` and real-driver
  `tests/spectator_tps_geometry.tscn` compare 630 clear cases, 24 controlled
  blocker/ridge cases and 48 moving orbit frames. The geometry scene checks the
  pull inputs and sample counts but excludes final hit-position equality;
  `tests/spectator_tps.tscn` retains the full strict gate and its two hit-distance
  failures below. Controlled query doubles do not certify actual world blockers,
  populated transport, browser `Math.hypot` or complete camera rendering.
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
  `node tools/player_tps_anchor_capture.mjs`,
  `node --test tests/player_tps_anchor.test.mjs` and real-driver
  `tests/player_tps_anchor.tscn` retain the original Chromium shoulder/floor
  branch and strict native Float32 comparison for imported heights, controlled
  surfaces, pitches and unbounded headings. The shared authority contract below
  blocks changes to this consumer. `node tools/player_view_body_capture.mjs`,
  `node --test tests/player_view_body.test.mjs` and real-driver
  `tests/player_view_body.tscn` retain the original movement-threshold and heading
  traces; its strict gate also remains open pending the authority contract below.
  Neither controlled fixture qualifies upstream precision, populated surfaces,
  clipping, ring placement, transport or rendered body/camera poses.
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
  A due draw freezes the window, mode, viewer, actor and bunker records, missiles
  and pulse for all layers; interpolated positions are captured after the caller
  refreshes them and before fog construction. Later mode/snapshot changes cannot
  mix a new crop or markers with the previously scheduled fog and lane paths.
  `node tools/minimap_frame_capture.mjs`, `node --test tests/minimap_frame.test.mjs`
  and real-driver `tests/minimap_frame.tscn` retain original draw/toggle programs,
  delayed native draws, observer and faction frames, missiles, remembered bunkers,
  legend colors, source window/crop/marker geometry and room retirement. The
  controlled sources do not qualify complete fog pixels, actual baked terrain,
  populated delivery or platform performance.
  Window edges retain scalar doubles through the committed terrain crop, marker,
  lane and hard/soft reveal plans; conversion occurs at the native drawing
  boundary. The label rounds the unconverted source width.
  `node tools/minimap_window_precision_capture.mjs`,
  `node --test tests/minimap_window_precision.test.mjs` and real-driver
  `tests/minimap_window_precision.tscn` compare 448 original source windows,
  projections, crops, labels and controlled reveal calls, including imported map
  bounds and zero/tiny axes. A live frame also checks the retained window across
  terrain changes. These probes use native-representable actor positions and do
  not qualify source position precision, baked terrain pixels, mask coverage or
  populated delivery.
  Marker and missile offsets are applied to the double projection before native
  primitive storage. `node tools/minimap_marker_precision_capture.mjs`,
  `node --test tests/minimap_marker_precision.test.mjs` and real-driver
  `tests/minimap_marker_precision.tscn` compare the original draw order and
  geometry for 96 controlled faction/observer frames, including the live canvas.
  These probes do not qualify marker edge coverage or populated actor rendering.
  `node tools/minimap_marker_raster_capture.mjs`,
  `node --test tests/minimap_marker_raster.test.mjs` and real-driver
  `tests/minimap_marker_raster.tscn` retain the original browser marker callback
  and isolated opaque rasters for fractional rectangles, circles, rings, bunker
  outlines, inherited widths, rotated arrows, clipping and overlaps. Keep the
  strict four-byte raster failures until the shared marker-coverage contract
  below is accepted; these probes do not qualify the full populated map.
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
  checks. A source detached or queued with an ancestor after selection must stop
  its own viewport before drawing; a queued PiP owner or owner ancestor releases
  every viewport and temporary layer at selection or the pre-draw boundary and
  cannot select again. Losing the last source restores the cockpit mask. A fresh
  selection is required after source reattachment.
  The selected pilot is weakly retained and rechecked before rendering; death,
  detachment, queued deletion of it or an ancestor, or freeing releases every
  viewport and temporary layer. Revival or reattachment needs a fresh selection.
  Hidden or detached PiP controls disconnect both global render callbacks;
  showing or reattaching reconnects them without restoring the retired selection.
  `node tools/pip_pilot_capture.mjs`, `node --test tests/pip_pilot.test.mjs` and
  real-driver `tests/pip_pilot.tscn` retain the original death/revival render
  decisions and native owner/source retirement checks. These controlled actors
  do not qualify populated transport or actual model pixels.
  Source selection, power limits and camera pose are refreshed before drawing.
  `node tools/pip_selection_capture.mjs`, `node --test tests/pip_selection.test.mjs`
  and real-driver `tests/pip_selection.tscn` compare 23 original render decisions
  for loss, death, recovery, insertion, removal, model replacement, movement and
  power changes. The real pre-draw test also checks controlled raster composition
  and world retirement. These cases do not qualify actual model pixels, populated
  transport, full frame ordering or performance.
  `node tools/pip_publication_capture.mjs`, `node --test tests/pip_publication.test.mjs`
  and `tests/pip_publication.tscn` compare the original selector on controlled
  snapshot membership with the native authority presentation. Keep the five
  failures across unpublished creation, loss, recovery and removal until the
  snapshot-lifetime contract below is accepted. These cases do not qualify
  populated delivery or actual model pixels.
  `node tools/pip_composition_capture.mjs`, `node --test tests/pip_composition.test.mjs`
  and real-driver `tests/pip_composition.tscn` compare the original Three.js/WebGL
  PiP render and complete opaque browser rasters at 320x568, 1440x900 and
  3840x2160, with one or two views. They retain same-frame scene color changes,
  faction borders, a declared foreground HUD layer, initially hidden cockpit and
  source models, low-power and resolution changes, hidden/reopened views, pilot
  death and lost-link cleanup. Source and native rasters currently agree byte for
  byte; do not loosen the shared raster tolerance. These controlled colors and
  empty scenes do not qualify actual source model pixels, authored HUD composition,
  DPI behavior, full-scene performance or populated transport. The separate
  `tests/pip_native.tscn` retains the full source-provenance gate below.
  `node tools/pip_window_capture.mjs`, `node --test tests/pip_window.test.mjs`
  and real-driver `tests/pip_window.tscn` compare the original WebGL border
  pixel bounds with the actual root-window PiP at eight controlled window/scale cases.
  Keep the seven strict failures and window witnesses below until the shared
  responsive-window contract is accepted. The non-unit ratios simulate the
  source CSS-to-framebuffer relation on a scale-1 display; they do not certify
  hardware DPI behavior, populated scene pixels or full HUD composition.
  Decoy and hero eye offsets are added as scalar doubles to the native model
  position before the camera vector enters Float32 storage. `tests/pip_pose.tscn`
  compares 26 original browser poses with Float32-representable model positions,
  including both signs and rounding boundaries, against the consumer plan and the
  actual camera. This does not qualify precision lost before the model position,
  camera rotation pixels, actor interpolation or populated source-model rendering.
  PiP yaw now consumes the existing `SourceQuaternion` axis-angle binding before
  native quaternion storage, so distinct source headings are not collapsed by
  an earlier Float32 angle conversion. `tests/pip_pose.tscn` retains that
  distinction; it does not establish exact source matrix composition.
  `tests/pip_orientation.tscn` retains the stricter original browser camera
  matrix and inverse-matrix gates, including inverse translation, across normal,
  boundary and unbounded reported yaw. The shared double-quaternion,
  browser-trigonometry and camera-transform contracts below remain open. A
  matching native quaternion alone cannot certify the final matrix bits or the
  Godot camera's render transform.

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
  Crawl frames, art/camera transitions, hold feedback, input and the exit fade
  use wall time while the scene tree is paused or gameplay speed is zero.
  Real-driver `tests/campaign_wall_clock.tscn` checks those boundaries against
  the existing original crawl and CSS references. Its controlled art and coarse
  scheduling checks do not qualify exact transition pixels or hardware input.
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
  The static backdrop expands by the original CSS inset before its centered
  scale; foreground motion does not move it. `node tools/campaign_backdrop_capture.mjs`,
  `node --test tests/campaign_backdrop.test.mjs` and real-driver
  `tests/campaign_backdrop.tscn` retain source bounds for twelve scale-1 viewports.
  The geometry comparison does not qualify image decoding, blur pixels, exact
  browser transform rounding or complete cinematic composition.
  The foreground uses the original CSS orientation boundary, clipped inner box,
  landscape borders and browser layout-unit inset; square viewports retain the
  portrait frame while the original camera function still selects its landscape
  pose. `node tools/campaign_frame_geometry_capture.mjs`,
  `node --test tests/campaign_frame_geometry.test.mjs` and real-driver
  `tests/campaign_frame_geometry.tscn` retain seventeen source frame sizes,
  camera targets and six controlled border rasters. Keep the three fractional
  raster failures and shared coverage contract below. These rasters omit the frame
  shadow and do not qualify original art, DPI or complete composition.
  The narrative card retains the original centered landscape/portrait bounds,
  CSS layout-unit quantization and bottom safe-area offset; square viewports use
  the portrait rule. The date and buffering/skip labels sit outside the crawl
  card, keeping its scroll viewport and finish control accessible. The source
  archive/date system bar is fixed to the viewport with its own 44 px horizontal
  and 5 px top padding, independent of the outer HUD's safe-area padding. `node
  tools/campaign_card_capture.mjs`, `node --test tests/campaign_card.test.mjs`
  and real-driver `tests/campaign_card.tscn` compare fifteen browser sizes and
  exercise the fixed bar, wrapped HUD labels, supplied safe insets and finish-button
  reachability. Native font advances determine the current bar's flex allocation;
  the native card border retains the captured source color, opacity and width,
  and the date label retains its source color and font size. Archive bold styling,
  source font metrics and actual text pixels remain unresolved.
  These checks do not qualify source text wrapping, the card's typography,
  gradient, blur, clipped corners, hardware safe areas or complete cinematic pixels.
  Scene selection updates the original date, badge and title as distinct fields;
  the badge and title share a horizontal header and the title can truncate.
  `node tools/campaign_heading_capture.mjs`,
  `node --test tests/campaign_heading.test.mjs` and real-driver
  `tests/campaign_heading.tscn` retain original scene changes, repeated and invalid
  indices, imported text and usable portrait/landscape header geometry. Native
  font metrics and header styling still require their separate visual contracts.
  The header panel retains source orientation-dependent padding, background and
  bottom-border values. `node tools/campaign_header_capture.mjs`,
  `node --test tests/campaign_header.test.mjs` and real-driver
  `tests/campaign_header.tscn` check those values and the remaining crawl viewport
  in portrait, landscape and square cases. They do not qualify text baselines,
  fractional coverage, the parent card's effects or complete header pixels.
  Each crawl section retains the original separate badge and prefixed title,
  including the source marker gap. `node tools/campaign_section_marker_capture.mjs`,
  `node --test tests/campaign_section_marker.test.mjs` and real-driver
  `tests/campaign_section_marker.tscn` compare the prologue and both first-chapter
  perspectives and check the marker controls at portrait/landscape sizes. The
  checks do not qualify source typography or complete section styling.
  The marker row retains the source bottom padding, solid border and margin to
  its paragraphs. `node tools/campaign_marker_geometry_capture.mjs`,
  `node --test tests/campaign_marker_geometry.test.mjs` and real-driver
  `tests/campaign_marker_geometry.tscn` check source border values, controlled
  section sizes including empty paragraphs, scroll bounds and focus progress. They
  do not qualify native text metrics, fractional border coverage or complete pixels.
  Crawl paragraphs remain separate, preserve original text and use the captured
  orientation-dependent inter-paragraph margin. `node
  tools/campaign_paragraph_capture.mjs`, `node --test tests/campaign_paragraph.test.mjs`
  and real-driver `tests/campaign_paragraph.tscn` compare browser DOM content and
  margins with native controls for the prologue and both first-chapter perspectives.
  These checks do not qualify text indent, line height, source wrapping or pixels.
  Active and inactive crawl sections retain the original opacity, 0.4 s ease
  transition and reversal-shortened durations. The initial selection, including a
  middle-chapter start, appears immediately; later changes animate independently
  on wall time. Each section isolates its content before applying group opacity
  and retires its render target and tween on removal.
  `node tools/campaign_section_opacity_capture.mjs`,
  `node --test tests/campaign_section_opacity.test.mjs` and real-driver
  `tests/campaign_section_opacity.tscn` compare original transition programs,
  initial and controlled overlapping-layer pixels inside the presentation group,
  and pause/visibility/retirement behavior. These controlled colors do not qualify
  actual text pixels, clipping at hardware DPI, full cinematic composition or
  the performance of populated sections.
  Section heights include the source bottom padding and reserved border width;
  the inter-section margin also precedes the ending block. `node
  tools/campaign_section_geometry_capture.mjs`,
  `node --test tests/campaign_section_geometry.test.mjs` and real-driver
  `tests/campaign_section_geometry.tscn` compare controlled scroll bounds, section
  offsets and focus progress in both orientations and a square viewport. Original
  dashed-border coverage is captured by
  `node tools/campaign_section_border_capture.mjs`,
  `node --test tests/campaign_section_border.test.mjs` and real-driver
  `tests/campaign_section_border.tscn`. The border remains undrawn pending the
  shared renderer contract below; actual text layout remains open.
  The crawl ending retains the source divider and distinct prologue/chapter notes.
  Prologue uses its original terminal button even when a caller supplies another
  label; a chapter uses its supplied label or the source fallback when empty.
  `node tools/campaign_ending_capture.mjs`, `node --test tests/campaign_ending.test.mjs`
  and real-driver `tests/campaign_ending.tscn` retain the original construction,
  both briefing labels and a real GUI click on the visible finish button.
  `node tools/campaign_ending_geometry_capture.mjs`,
  `node --test tests/campaign_ending_geometry.test.mjs` and real-driver
  `tests/campaign_ending_geometry.tscn` compare the source ending's padding,
  divider and note spacing, scroll limit and focus with controlled element heights
  in three orientations. The finish button also retains the computed source
  content insets, font size and pointer cursor. The `.btn.big` selector overrides
  the later, less-specific `.prologue-finish-btn` declarations.
  `node tools/campaign_finish_button_capture.mjs`,
  `node --test tests/campaign_finish_button.test.mjs` and real-driver
  `tests/campaign_finish_button.tscn` check those insets in normal, hover, pressed
  and disabled states and controlled content boxes at three viewport sizes. Actual typography,
  letter spacing, text wrapping, button colors, notch and the caller contract
  below remain unqualified.
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
  The crawl viewport retains the source landscape/portrait padding, including the
  portrait rule for square viewports. Section focus and deferred chapter jumps
  include its top inset; the bottom inset contributes to scroll clamping.
  `node tools/campaign_crawl_insets_capture.mjs`,
  `node --test tests/campaign_crawl_insets.test.mjs` and real-driver
  `tests/campaign_crawl_insets.tscn` compare original padded geometry, focus,
  camera targets, chapter jumps and native GUI wheel/touch propagation. Controlled
  section sizes do not qualify source typography, scrollbar pixels or hardware input.
  `node tools/campaign_scrollbar_capture.mjs`,
  `node --test tests/campaign_scrollbar.test.mjs` and real-driver
  `tests/campaign_scrollbar.tscn` retain original classic-scrollbar dimensions,
  controlled thumb rasters and scroll positions with the separate edge mask
  disabled. Keep the strict width and pixel failures and shared adapter contract
  below; these cases do not qualify overlay scrollbars, hardware DPI or input.
  `node tools/campaign_crawl_mask_capture.mjs`,
  `node --test tests/campaign_crawl_mask.test.mjs` and real-driver
  `tests/campaign_crawl_mask.tscn` retain original edge-mask pixels and unmasked
  controls. Keep the three strict mask failures and renderer contract below;
  controlled color layers do not qualify text, scrollbars or full cinematics.
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
  A completed long press cancels and resets its feedback before checking the
  buffer, including repeated blocked attempts and a later successful skip.
  `node tools/campaign_hold_warning_capture.mjs`,
  `node --test tests/campaign_hold_warning.test.mjs` and real-driver
  `tests/campaign_hold_warning.tscn` retain the original warning/hold sequence.
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
  bypass. A non-prologue chapter starts already ready, displays the original ready
  status and skip hint, and never starts another buffer. Replacing a prologue with
  a chapter must reject retired progress callbacks without hiding that status.
  `node tools/campaign_chapter_status_capture.mjs`,
  `node --test tests/campaign_chapter_status.test.mjs` and real-driver
  `tests/campaign_chapter_status.tscn` retain both original play branches, progress,
  immediate chapter skipping and replacement. Status visibility callbacks may
  retire, detach or queue the owner without starting stale buffering or clocks.
  These checks do not certify status icon, color or flash pixels. Failed attempts
  count toward progress, not asset availability. Preserve independent 1800 ms
  warning deadlines, generation checks and decoder drains across replacement/exit,
  including pause and zero gameplay speed. Original model
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

- **Flash — cinematic chapter return label:** tracked in
  [F2](../flash/MIGRATION.md#ready-for-bounded-implementation). Terra retains
  `CampaignCinematic.play()` and its source-derived default/override contract;
  the caller correction requires no Terra producer or shared-label change.

- **Opus — shared campaign dialogue deadline fixture:** update
  `tests/campaign_suite.gd::dialogue_lifecycle` to advance a controlled wall
  clock before expecting the next radio line. The fixture currently emits a
  fresh timer immediately and expects delivery before its source deadline;
  `CampaignDialogue` correctly rearms that early signal, as retained by
  `tests/dialogue_clock.tscn`. Preserve the retired-generation cancellation
  check, verify that an early signal does not advance the line and that the
  deadline advances it once. Acceptance: both dialogue clock and campaign
  lifecycle assertions pass; the separate missing campaign terrain resources
  remain an independent acceptance gate.

- **Opus — PiP recipient snapshot lifetime:** define the recipient presentation
  boundary in `scripts/simulation.gd::apply_presentation_view`,
  `scripts/unit.gd` and, if needed, `scripts/main.gd::_receive_state`, before
  Terra binds `scripts/pip_view.gd` to it. The original client selects from its
  received entity map and updates a decoy's lost flag only on receipt. The native
  authority instead exposes live `units` and `special`; new units default to
  `presentation_visible = true`, and a removed carrier is erased and queued
  before the next presentation snapshot. In `tests/pip_publication.tscn`, a newly
  created decoy appears before publication, loss and recovery take effect early,
  and a removed decoy disappears while the prior snapshot still contains it.
  Acceptance: expose recipient snapshot membership, loss state and renderable
  lifetime through the publication boundary without changing combat authority;
  pass all eleven original selection steps and existing PiP lifecycle/composition
  tests, then verify offline, ENet and WebSocket with populated carriers. The
  controlled snapshot program alone does not qualify delivery or real model pixels.

- **Opus — responsive root window:** establish a shared full-client-area and
  pixel-ratio contract in `project.godot` and `scripts/main.gd::_build_ui` before
  Terra retargets the `PipView` window coordinates. The current canvas-items
  stretch fixes the visible viewport at 1440×900 and letterboxes other aspect
  ratios. With a real 320×568 window at display scale 1, the original Chromium
  PiP border bounds are `[10, 56, 58, 37]` pixels, while native bounds are
  `[2, 196, 56, 35]`; at 640×360 they are `[10, 56, 113, 72]` and
  `[36, 22, 100, 63]`. Even the same-aspect 720×450 window produces
  `[5, 28, 124, 78]` instead of `[10, 56, 126, 80]`, because fixed source
  margins are scaled. `tests/pip_window.tscn` keeps seven of eight original
  window/scale cases failing; captured bounds remain in
  `artifacts/terra/pip-window-report.json` and the 1440×900 control passes.
  New evidence requires an unused directory via `--evidence-dir`.
  Coordinate and clipping changes must preserve the main camera, HUD, minimap,
  scope and input consumers. Acceptance: the strict source/native border bounds
  and existing `tests/pip_composition.tscn` pass at portrait and landscape
  sizes, followed by actual hardware-DPI and populated match checks. Simulated
  pixel ratios alone do not qualify hardware-DPI or actor rendering.

- **Opus — shared player camera and body heading:** agree an authority/presentation
  contract for `scripts/simulation.gd::camera_origin_at`/`third_person_camera`
  and `scripts/unit.gd::advance_player_view` before Terra changes
  `scripts/camera_pose.gd::third_person_anchor` or
  `scripts/player_view_state.gd::advance_body`. The same helpers feed both the
  displayed camera/body and authority view origins, muzzle targeting, blast
  feedback and reported body headings. In controlled native-representable inputs,
  `tests/player_tps_anchor.tscn` currently disagrees with the captured Chromium
  query or camera Float32 values in 312 of 720 cases; the original method uses
  scalar-double shoulder, height and floor arithmetic before native conversion.
  `tests/player_view_body.tscn` retains 96 failing consecutive-frame assertions
  because native Vector3 squared-length rounding crosses the original strict
  threshold in both directions. Acceptance: preserve authority settlement and
  visibility while defining which side owns these boundaries, then pass both
  strict source fixtures, the player-view suite and populated TPS ENet/WebSocket
  cases. Terra binds an accepted presentation contract in a separate change;
  the controlled fixtures cannot establish upstream precision or populated worlds.

- **Sol — camera obstruction hit distance:** agree a source-faithful segment-hit
  contract for `scripts/world.gd::obstruction_hit` before Terra changes the
  collision binding in `scripts/spectator_camera.gd` and
  `scripts/camera_pose.gd`. The original `_blockerHitT` returns a scalar hit
  distance from the double-precision segment; the existing world API returns a
  native Vector3 hit position. In the controlled four-metre ray cases 652/653 of
  `tests/fixtures/spectator_tps.json`, constructing that native hit position and
  measuring it from the original anchor yields 3.99999989123131 m. The resulting
  final z is 1.6303430795669556 instead of 1.6303431987762451, so the strict
  `tests/spectator_tps.tscn` keeps both failures. Native/source witnesses are in
  `artifacts/terra/spectator-tps-final.json`; these are controlled rays, not a
  populated world qualification. Preserve collision masks, segment ordering and
  real blocker geometry. Acceptance: publish source-equivalent scalar distances
  for the original double endpoints, pass the strict captured and additional
  boundary cases without fabricated distances or wider tolerances, then verify
  actual world obstruction, terrain and player/spectator camera integration.
  Terra binds the accepted producer contract in a separate change.

- **Models — source camera quaternion composition:** provide a double-preserving
  yaw-to-basis contract in `scripts/source_quaternion.gd` for consumers including
  `PipView`. Original Three.js composes its camera matrix from double quaternion
  components before Float32 matrix storage; `SourceQuaternion.axis_angle` and
  `SourceQuaternion.basis` currently store the quaternion in Float32 first.
  Chromium quaternion and final matrix bits at normal, ±π/2 and large reported
  yaw are retained in `tests/fixtures/pip_composition.json::poseCases`, with
  before/after native basis and scalar witnesses in
  `artifacts/terra/pip-orientation-report.json`. At yaw 1000000.02, maximum
  basis error falls from 0.0188037753105164 to 0.000000059604644775390625,
  but the strict matrix gate still fails.
  Acceptance: direct results match every captured Float32 camera basis, with
  unbounded yaw, source operation order and no tolerance widening; preserve
  existing model and spectator APIs. The required browser sine/cosine and native
  camera-transform contracts remain Opus-owned below. After those are accepted,
  `tests/pip_orientation.tscn` must also pass through the actual PiP camera.
  Terra binds the accepted API separately.
- **Opus — PiP camera-transform boundary:** investigate a native camera binding
  in `scripts/source_camera_transform.gd` if an adapter is needed, preserving
  the original Three.js camera world and inverse transform in the existing
  `Camera3D`/`SubViewport` path. At yaw 1000000.02 the captured Float32 basis is
  retained by `Camera3D.transform.basis`, but both `global_basis` and
  `get_camera_transform()` differ by one Float32 ULP; the latter's
  `affine_inverse()` differs from the captured Three.js inverse as well.
  Godot 4.7.2's [`Camera3D`](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/3d/camera_3d.cpp)
  orthonormalizes its camera transform, and its
  [`RendererSceneCull`](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_scene_cull.cpp)
  also orthonormalizes transforms sent through `RenderingServer`; simply toggling
  `set_disable_scale` or writing the same matrix directly cannot establish the
  captured view matrix. The project uses GL Compatibility, whose
  [GLES3 renderer](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp)
  takes an affine inverse after the server boundary. The native fixture mirrors
  that extra normalization and inverse in its CPU comparison. Twelve captured
  inverse translations differ, by up to 0.0001220703125 on the controlled
  Float32-representable model positions. The source matrix and inverse and both
  native values are recorded in
  `tests/fixtures/pip_composition.json::poseCases` and
  `artifacts/terra/pip-orientation-report.json`. This CPU comparison does not
  certify GPU uniforms or scene pixels. Acceptance: the original world and
  view-matrix rotation and translation cases pass `tests/pip_orientation.tscn`
  through the actual PiP camera after the Models quaternion and browser trig contracts,
  with no wider tolerance, plus real-driver PiP source-pixel comparisons.
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
  Node-only capture is insufficient to choose the shared browser binding. The
  same shared API must expose browser `Math.sin` and `Math.cos` for PiP yaw
  half-angles in `tests/fixtures/pip_composition.json::poseCases`; native scalar
  bits differ from Chromium for several captured inputs. Acceptance includes
  both functions and the PiP orientation cases without input-specific tables.

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
- **Opus — player look and view-lock angle transfer:** agree a double-preserving
  contract across `scripts/main.gd::_look`/`_advance_view`,
  `scripts/input_rules.gd::look` and Terra's `ViewLockState.advance`. The current
  `Vector2` arguments and results quantize base angles and lock increments;
  even the frozen branch rewrites angles. The original `_applyLook` retains
  1024.251199999997 after forty 0.00003-radian steps from 1024.25, while native
  remains at 1024.25. A frozen angle of 1024.25003 remains unchanged in the
  original and becomes 1024.25 natively; one captured tracking step ends at
  1024.236406260541 versus 1024.2364501953125. Read-only source and native
  programs are retained in `artifacts/terra/view-lock-precision-source.mjs` and
  `artifacts/terra/view-lock-precision.tscn`; the existing shared `rng.js`
  provenance mismatch still gates published captures. Acceptance: original
  free-look and lock sequences retain unbounded yaw, sub-Float32 increments,
  strict frozen no-op, pitch limits, inversion, recoil and previous-rendered
  projection across FPV/TPS; do not alter authority settlement. Terra updates
  its consumer separately after the producer contract is accepted.
- **Opus — view-lock scalar distance:** publish an accepted browser
  `Math.hypot(x, z)` binding in `scripts/source_numeric.gd`, checking the existing
  `CarrierRules.hypot2` implementation and its narrower carrier fixture first.
  `ViewLockState.advance` currently rounds target-minus-eye through `Vector3`
  and horizontal length through `Vector2` before tracking. With the same native
  Float32 inputs, the original Node program in
  `artifacts/terra/view-lock-precision-source.mjs` produces Float32 steps
  `[0.014999998733401299, 0.015000004321336746]`; the native diagnostic produces
  `[0.014999999664723873, 0.015000000596046448]`. These are controlled inputs,
  not a populated targeting or browser-bit qualification. Acceptance: the
  shared adapter matches original Chromium two-argument results across source
  coordinates, zero, subnormal and non-finite inputs without tables or wider
  tolerances. Terra then keeps subtraction in scalar doubles and validates both
  axes before native storage with the original view-lock program.
### Shared-owner contracts required for presentation

- **Opus — spectator, minimap, PiP, scope and dialogue provenance:** reconcile the original
  `public/js/rng.js` dependency through `tools/import_source.mjs` and
  `data/provenance.json` before full spectator, minimap, dialogue, scope and PiP qualification.
  The captures `tests/fixtures/spectator_native.json`, `tests/fixtures/minimap_native.json`,
  `tests/fixtures/dialogue_native.json`, `tests/fixtures/dialogue_transcript.json`,
  `tests/fixtures/scope_raster.json` and `tests/fixtures/pip.json` declare
  `96773f680724e2fc8e695270333d41d3a18e539dabb88968dad0b9cb68fae654`,
  while shared provenance declares
  `c46913b415a75aa5f0d2366dd7bfcb4f8f26c1db913ecea2a74b40695dd78aaa`.
  Preserve the full captures and their source guards. Acceptance: original
  spectator, minimap, automatic radio, transcript, scope and PiP programs pass with the agreed
  complete source inputs and unchanged timing/asset comparisons;
  `tools/spectator_native_capture.mjs`, `tests/spectator_native.tscn`,
  `tools/minimap_native_capture.mjs`, `tests/minimap_native.tscn`,
  `tools/pip_capture.mjs`, `tests/pip_native.tscn`, `tools/scope_raster_capture.mjs`
  and `tests/scope_raster.tscn` must also accept the shared identity. The narrower
  cancellation oracle cannot substitute for these checks or certify populated
  delivery.
- **Flash — settlement transcript host:** tracked as blocked
  [F4](../flash/MIGRATION.md#blocked-on-accepted-producer-contracts). Terra keeps
  the inner dialogue geometry, 42vh cap, portrait slots and scrolling contract;
  accepted font/material bindings below remain prerequisites for full host pixels.
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

- **Opus — source scrollbar geometry and input:** agree a shared native binding
  in `scripts/source_scrollbar.gd`, with a material under `shaders/` if needed,
  before Terra replaces the default scrollbar in `scripts/campaign_cinematic.gd`.
  The captured classic browser scrollbar has a 4 px transparent track and a
  2 px radius thumb in `rgba(95,208,242,0.25)`; native currently reserves 8 px.
  At 320×100 with overflow, source content is 316 px wide and native is 312 px.
  All captured scroll offsets and the no-overflow control pass, but the 16
  overflowing cases in `tests/campaign_scrollbar.tscn` retain 32 strict width
  and raster failures. A 4 px native-style diagnostic fixes width and matches
  both ends of the 320×100/400 px case, but differs at its midpoint by 14 pixels;
  in the 96×24/400 px case, the source thumb covers 17 rows and the diagnostic
  covers two, differing in 68 pixels at the unchanged two-byte gate. At (94,16),
  source RGBA is `[37,94,125,255]` and the diagnostic is `[20,60,90,255]`.
  Browser PNGs and sampled thumb bounds are in
  `tests/fixtures/campaign_scrollbar.json`; current and diagnostic images are in
  `artifacts/terra/campaign-scrollbar-probe-154cd6b2/`. The capture enables
  Chromium's classic scrollbar and disables only the separate viewport mask.
  Preserve source visibility, reserved width, minimum thumb, integer placement,
  color and rounded coverage, plus native scroll values, wheel/touch, thumb drag,
  track interaction and lifecycle. Acceptance: all seventeen original cases and
  additional fractional-size, DPI and actual input programs pass without wider
  tolerance or per-case baked images. Terra then binds the accepted adapter and
  checks the edge mask, populated narrative, scrolling and complete composition.

- **Opus — cinematic section dashed border:** agree a native material or
  rendering binding under `shaders/campaign_section_border.gdshader` for
  `scripts/campaign_crawl_section.gd`. The original one-pixel border is dashed
  `rgba(122,158,178,0.16)`; its dash positions and edge coverage vary with the
  section width. At the unchanged two-byte gate, the currently undrawn border
  differs in 76/81/248/248/501 pixels at widths 96/101/320/319/641. A native
  `draw_dashed_line` diagnostic using the captured initial three-pixel dash still
  differs in 63/66/211/208/430 pixels, with maximum channel difference 27 bytes.
  Original PNGs are in `tests/fixtures/campaign_section_border.json`; source,
  current and diagnostic images are in
  `artifacts/terra/campaign-section-border-probe-62fc93b4/`. Preserve the
  width-dependent dash placement, fractional coverage, source color and alpha,
  and place the line within the section's isolated opacity group before scroll
  clipping and the outer presentation fade. Acceptance: Opus validates all five
  original rasters and further fractional-width and DPI cases without wider
  tolerance or per-size baked images. Terra then binds the agreed renderer and
  checks `tests/campaign_section_border.tscn`, scrolling and full composition.

- **Opus — cinematic crawl edge mask:** publish an accepted binding in
  `shaders/campaign_crawl_mask.gdshader` for the scroll viewport consumed by
  `scripts/campaign_cinematic.gd`. The original viewport masks its already-composed
  contents with a vertical alpha gradient: transparent at 0%, opaque at 4% and
  95%, then transparent at 100%. The native scroll viewport currently has no mask.
  At the unchanged two-byte raster gate, the three original mask cases at 96×64,
  101×73 and 320×100 differ in 576, 707 and 2,880 pixels, with maximum channel
  differences of 137, 140 and 146 bytes; all three unmasked controls pass.
  At the top-right pixel of the 96×64 case, source RGBA is `[21,61,80,255]`
  and native is `[40,180,210,255]`. The original PNGs are retained in
  `tests/fixtures/campaign_crawl_mask.json`; isolated source/native images and
  witnesses are in `artifacts/terra/campaign-crawl-mask-9f0a12d8/`. The material
  contract uses viewport-local, unscrolled coordinates on already-composed
  premultiplied RGBA; scale both RGB and alpha by the original mask. Preserve
  scrolling and the outer presentation fade. Acceptance: Opus validates its
  material against the three enabled source rasters and additional fractional-size
  cases without wider tolerances or baked per-size images. Terra then binds the
  agreed material, adapts `tests/campaign_crawl_mask.tscn` to disable that binding
  for its unmasked controls, and checks all six rasters, visible scrollbars,
  populated text, touch scrolling and complete cinematic composition.

- **Opus — cinematic fractional frame coverage:** agree a native material or
  rendering binding under `shaders/campaign_frame*.gdshader` for the clipped
  foreground and its translucent one-pixel borders in
  `scripts/campaign_art_layer.gd`. The source and native frame/image bounds agree,
  but the unchanged two-byte `tests/campaign_frame_geometry.tscn` raster gate
  differs at 501×500, 377×376 and 641×640: respectively 1,000, 1,128 and 1,280
  pixels exceed two bytes, with maximum channel differences 23, 151 and 36.
  For 377×376 at row 188, source pixels 364/365 are `[48,144,208]` and
  `[29,39,45]`; native pixels are `[37,49,57]` and `[5,7,10]`. Captured source
  rasters are in `tests/fixtures/campaign_frame_geometry.json`; isolated native
  and source images can be regenerated with an unused `--evidence-dir`.
  Preserve the CSS layout-unit positions, clip/border order, alpha and camera
  transforms. Acceptance: all six captured rasters plus additional fractional
  frame positions pass without wider tolerance or per-size baked images, then
  recheck original art, shadows, DPI and populated cinematic composition.

- **Opus — minimap marker coverage:** agree native bindings under
  `shaders/minimap_marker*.gdshader` before Terra replaces the marker drawing in
  `scripts/minimap.gd`. The original Canvas2D callback and Chromium PNGs in
  `tests/fixtures/minimap_marker_raster.json` disagree with the native draw calls
  in all twelve controlled cases at the existing four-byte gate: 1,032 pixels
  exceed four bytes in total, with maximum channel difference 117. Integer base,
  fractional tower, enemy hero and rotated-arrow cases differ in 156, 39, 82 and
  31 pixels respectively. Exact byte and native image evidence is in
  `artifacts/terra/minimap-markers/msaa0-ss1/`. Godot's
  [Compatibility renderer does not support 2D MSAA](https://docs.godotengine.org/en/4.7/tutorials/2d/2d_antialiasing.html);
  configured 2x/4x/8x tests produced the same result. A separate CPU Lanczos
  downsampling experiment and disabling rectangle antialiasing did not pass the
  strict cases. Preserve source geometry, inherited line widths, subpixel
  placement, alpha composition, faction colors and draw order. Acceptance:
  `tests/minimap_marker_raster.tscn` passes every captured original raster and
  further rotated/overlap cases without wider tolerances or baked per-case images,
  followed by the complete minimap composition and populated lifecycle tests.
  Terra binds the accepted shared renderer in a separate change.
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
- **Opus — weather-gradient lifetime:** separate the weather gradient's mode and
  outer scoped stop from the current scope mode and ring radius in
  `shaders/scope_mask.gdshader`. The original `weatherFog` callback keeps its last
  CSS background when density reaches zero, while its opacity fades for 0.5 s;
  the scope ring and aiming mode can change independently during that fade. In
  `tests/fixtures/scope_values.json::programs`, a scoped weather gradient retains
  9.8/17.8 vmin while the ring moves to 22.4 vmin. Native currently reuses
  `radius_vmin` and `scoped` for both layers. `tests/scope_weather_retention.tscn`
  retains four failures across radius changes and scope toggles; the unscoped
  no-toggle fade passes. Preserve independent parameters and the original fade,
  gradients and ring composition. Acceptance: Terra binds the agreed parameters
  and updates this strict scene to read them, all captured retention programs and
  transition/raster tests pass, and no wider pixel tolerance is used.
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

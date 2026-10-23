# Authority, integration and difficult source semantics — outstanding work

Read [AGENTS.md](AGENTS.md). Current source metadata, fixture coverage and combined
runtime acceptance remain incomplete. Component results do not certify the build.

## Live blockers and high-risk fidelity

- [ ] **O1 — Current source publication:** reconcile required runtime metadata,
  source hashes and fixture generators with the current code. Regenerate missing
  or stale controls/visual/deployment/HUD/mode references through the canonical
  importer; audit current availability rather than preserving obsolete missing-
  metadata lists. Publish complete fixtures/manifests atomically and register
  owner-provided suites without concurrent writers.
- [ ] **O2 — Procedural music envelopes:** resolve the full-suite music gain
  failure with sample-level source/native comparison. The unresolved interaction
  is pending exponential ramp endpoints, `setTargetAtTime` and cancellation;
  54 mismatches were reported and no proven root cause is established. Primary
  edit surface: `scripts/audio_music_envelope.gd`,
  `tools/audio_music_gain_capture.mjs`,
  `tests/audio_music_envelope_suite.gd`. Keep gain-before-filter ordering and
  source timing; do not substitute a generic fade or relax tolerances. Playback,
  resampling and audible integration remain separate Sol acceptance.
- [ ] **O3 — Full native surface shaders:** translate and mount original toon/
  built-in/School B programs, curve/ink/shadow hooks, material-style/light finish,
  custom vertex/instance attributes and typed uniforms. Compose alpha, shield,
  weather, occlusion and dissolve without losing source frames or material aliases.
  Finish source MRT outline sentinel, shield glyph orientation and alpha/HDR/post
  composition rather than accepting isolated shader compilation as equivalence.
  Captured GLSL/ShaderChunks are source data, not an implemented native shader.
- [ ] **O4 — Outlines and screen edges:** finish source shell visibility/LOD,
  world building detail and the separate screen-space world-edge pipeline.
  Certify world-scale normalization, mirrored/nonuniform/sheared/zero scales,
  source NDC clamps, local expansion, culling, camera masks and PiP isolation.
  Complete shader lighting/curvature agreement and real GPU pixels; a fixed-width
  fallback cannot establish source equivalence.
- [ ] **O5 — Texture/sampler acceptance:** finish colour-space output,
  anisotropy/filter/mip/native GPU equivalence, custom scalar/storage combinations,
  typed sampler and uniform bit fidelity, model/world material binding and
  authored mip handling. Preserve original negative zero, half/float channels,
  explicit null versus undefined, matrix fourth rows and source integer/bool
  coercion. Streaming resolution, virtual pages and demand/eviction lifecycle
  remain unimplemented. Use actual source GPU readback where CPU UV rules differ.

## Coupled simulation semantics

- [ ] **O6 — Weapons/targeting:** finish complete source muzzle/model-centre,
  animated visual-mesh envelopes, source reachability/report/impact timing and
  moving-target hit prediction and combined aiming/body/status behavior.
  Preserve authority lock throttles,
  confirmed-anchor hysteresis, target-dependent ranges, immutable launch frames,
  FNF continuation, direct/fan/line visibility and intentional blast coverage.
  Mesh/rig changes are Models handoffs; harmless effects are Sol handoffs.
- [ ] **O7 — Active abilities/status:** certify cast channels, squared
  interruption fractions, charges/cooldowns, shield/evasion/suppression/critical/
  elemental order, source defensive sectors, healing, phase/reflect and immunity.
  Finish weather/projectile/visibility/aiming/scenery interactions, source
  carrier/clone/summon/hologram lifetimes and complete entity targeting. Cube
  planes and tactical fog need combined LOS, barrier, poison and protection cases.
- [ ] **O8 — Carrier/companion settlement:** certify launch origins, fractional
  SUPER counts, bomber drops, kamikaze/hypersonic tracking/scatter, arrival order,
  interception and owner-dead versus owner-absent behavior. Zero budgets must not
  invent effects. Source companions retain distinct body/sight height bands,
  expiry/lethal swaps, assist/focus/credit rules and no invented summon lifetime.
  Missing generated model content must reject before spending.
- [ ] **O9 — Traversal and visibility:** finish complete support/slope/climb/
  collision order on terrain, roofs, bridges, tunnels, galleries, scenery and
  frozen fluids. Preserve source planar progress, per-layer blast separation,
  rooftop height references, grazing-obstacle tolerance, registered pad anchors,
  native crowd pushes and source spawn/clearance. Certify dynamic blockers,
  environmental LOS/team sight, status/field visibility and audibility contracts.
- [ ] **O10 — Movement/environment:** certify charged jump/morph/lift/hover,
  altitude, sink/unbalance, shallow/full/frozen immersion, marine tide lift and
  ice floor/ceiling/DOT behavior in complete tick order. Integrate seven-dimensional
  weather, thermal history, solar/night accuracy, cadence/reload/cooldown/damage,
  independent snow/lightning, fire/quench and full surface/hazard effects.
- [ ] **O11 — Physical scenery:** finish source hazard/vehicle/mine/AA/relay
  seeding, connectivity/corridor pruning, environment indexing, destruction and
  flood movement/jump integration. Preserve source rubble blocking, co-located
  blocker selection, seeded salvage/fire, mine airborne exclusions and AA report
  budgets. Geometry/damage deformation and source scenes are external model inputs.
- [ ] **O12 — Waves/NPC/economy:** certify complete prefill/spacing/cohesion,
  mirrored jitter and combat draws, 8 Hz stepping, held-target/rescan ordering,
  weather/support/traversal and NPC blast settlement. Finish all eight upgrade
  tracks, lane creep upgrades, remote/dead purchases, assists/bounties/penalties,
  loot/affixes/salvage, battery overcharge/recharge deadlines and supply/heal gates.
- [ ] **O13 — Camps/civilians/stats:** finish camp placement/clearance,
  garrison protection/healing, tether/aggro, liberation/respawn and civilian/spy
  follow/away/wander/aid/death behavior. Preserve private spy identity, per-ID
  source body/appearance rules, interaction eligibility and event recipients.
  Complete per-body/squad/mode stats, damage/leaderboards, kill/assist/weighted
  last-hit credit and replay-safe public HUD data.
- [ ] **O14 — Bots:** integrate source difficulty/role policies, constructor
  draws, global/per-operation APM deadlines, threat/alert/scope search, bounded
  turns and action priorities with traversal, BOSS/SUPER and full frame order.
  Preserve original evasion inputs, history retention/backdating, every-third
  light report and resource settlement. Compare seeded complete matches.
- [ ] **O15 — Balance initialization:** certify source preference normalization,
  constructor-time building DPS redistribution, cached range/mobility midpoints,
  first-use reach/curvature/history/role caches and ordinary offline versus
  dedicated factory preferences. Preserve later-slider non-recomputation and
  surviving nonpositive HP after a capacity adjustment until actual damage kills.
- [ ] **O16 — Controls and owner ordering:** certify source wheel/RMB/F/keypad,
  frozen/blind gates, local cast-point capture, confirmed-lock eligibility,
  monotonic mode acknowledgement, empty-heavy fallback, recoil/echo/movement
  order, pre-kick launch direction and distinct RNG/resource budgets. Complete
  authoritative heading/camera/muzzle convergence and combined input/cast/
  purchase timing. Personal/touch/gyro prediction remains a Sol consumer.

## Modes and room lifecycle

- [ ] **O17 — BOSS/campaign/SUPER:** certify authored chapter maps/rosters,
  stage locks, segment upgrades/HP floors, dialogue gates, permanent BOSS death,
  immunity and progress eligibility. Finish SUPER fractional curves, absolute
  body/aim/collision scaling, separate spawn sampling, both-base repairs,
  third-faction stats, auto shop and mode-specific recovery/observer behavior.
  Require generated source resources; missing chapters or SUPER metadata stay
  unavailable. Full transitions, source frame order and chapter lifecycles remain open.
- [ ] **O18 — Membership/readiness/loading:** certify logical-seat/physical-
  route separation, bot capacity/selection, ready cancellation, source loaded
  barrier and deferred authority population. Verify live ordinary seat/side edits,
  fixed join mode, unseated vision/input restrictions and no implicit actor
  replacement. Prebuild consumption and progress/error wiring must use Sol's
  actual resource state rather than starting simulation early.
- [ ] **O19 — Observers/privacy:** certify explicit/late admission, capacity
  bypass, no readiness/progress contribution, shared world preparation and camera
  restoration. Complete recipient-specific snapshots/events, public special-role
  whitelists, clone/player identity, owner-only magazines/recharge/lift/view,
  status summaries and stale replica clearing across all populated modes.
- [ ] **O20 — Recovery/leave/cleanup:** certify retry backoff, held human
  seats, credential persistence/revisions, stale route revocation, explicit leave
  acknowledgement, owner-seat departure with retained battle bodies and no-human
  cleanup. Preserve latest-120 disconnected input/action FIFO, reliable ordering,
  unsent suffix retention and reclaim-before-flush. Test loss, delay and failure
  without crossing match IDs or leaking private state.
- [ ] **O21 — Rematch/replay/fatal lifecycle:** certify retained seats and
  credentials, base re-roll/architecture seed, prebuild invalidation and old-round
  packet rejection. Verify complete quick-start recipes, authored-arena room size,
  source definition identity, isolated storage and story-free quick replays.
  Finish watchdog background-time exclusion, load/snapshot/disconnect errors,
  solo-only restart and first-failure propagation without killing a listener.
- [ ] **O22 — Room services/deployment:** implement only source-defined
  PIN/discovery/multiroom hosting, favorites, public/private directory policy,
  live geographic preparation/qualification, cache refresh and relay fallback.
  Finish remote creation, procedural/random recipes and unsupported custom maps
  when their original semantics exist; never fabricate a map or privacy guarantee.

## Full-build acceptance

- [ ] **O23 — Shared integration:** pull exact cross-owner interface requests,
  regenerate required content once, then run the full current fixture suite,
  populated runtime/render/lifecycle checks and both transports. Audit true
  source event/frame order and platform behavior; focused math or storage checks
  cannot substitute for complete match comparison. Resolve new failures before
  calling a path verified.
- [ ] **O24 — Delivery:** certify native exports, mobile sensors/safe areas,
  Compatibility rendering, memory/performance, threaded audio on Web, browser
  single-player, Pages artifact contents and production native hosting. Complete
  transport loss/bandwidth/MTU and cleanup acceptance on the current build.

Baseline commands from the repository root:

```powershell
godot --headless --path . res://tests/run.tscn
godot --headless --path . -- --smoke
./tools/test_network.ps1 -Godot C:/path/to/godot_console.exe
```

Select relevant existing case switches in `tools/test_network.ps1` one per run
for membership/loading/roster, observers, recovery/rematch/restart/fatal, balance,
controls, weapons, bots, BOSS, campaign and SUPER. The wrapper runs ENet and
WebSocket. Add world/model/render/export checks only as required by the change.

## Unsupported source paths

The current source has `SQUAD.N = 1`, `SQUAD.DMG = 1` and `support=false`.
Legacy formation/follow/body-swap/wing salvos and storm/boomerang/tree/moon/
harpoon/link/mine/infection/support helper branches have no active authored
`heroCast` producer. Keep them unavailable unless an active source producer is
found and implemented with original fixtures. This restriction does not disable
the source's active world mines, carriers, clones or autonomous summons.

Keep only current failures and exact interface requests here. Delete completed
items without copying old logs, passed assertion totals or superseded attempts.

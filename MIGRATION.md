# Feature parity ledger

This ledger distinguishes imported source content from implemented native
behavior. A passing math fixture does not establish full match equivalence.

Current status/ability/movement/companion/carrier/NPC/economy/wave/weather/environment/scenery/field-threat/loot/supply/camp/civilian/match-stat/missile-defense/aiming-presentation/bot/boss-siege/campaign/super/controls-recoil/touch-gyro-controls/view-lock-scope/player-view-foundation/body-assets-weapons/per-part-morph/gait-foundation/biped-hop-aerial-quad-vehicle/body-combat-clocks/jump-pose/cast-pose/species-pose/world-aim-anatomical-equipment/NPC-shot-bursts/hero-discharge-fan work is unverified. At the user's request,
fixture generation, Godot compilation, runtime/render smoke checks and transport
tests are deferred until all migration implementation is complete. The new
source-oracle modules and native suites are written but have not been executed;
the saved fixtures and validation results below still describe the earlier build.

| System | Native status | Remaining parity work |
| --- | --- | --- |
| Project/runtime | GDScript main scene and autoloads; no runtime JS | Platform exports and delivery builds |
| Character content | All 32 pilots, four weapon/ability tiers, chassis stats | Some mechanics below remain unavailable |
| Art | Original reference/combat/faction glTF and audio imported; native animation playback; all 32 source-built FPV cockpits, source gun-root/mirror/burst/flash poses; 128 source projectile scenes with age/speed opacity/tail animation, private owner poses and FPV echo shell/thin-tracer flight | Combat attachments, full morph/body/view reaction, remote/TPS projectile mounts and interpolation, muzzle/impact particles, toon/outline shaders, damage states |
| Map layouts | 18 qualified presets, all five team sizes, source lane subsets/tower pairs; 90 native terrain/road resources; original triangular terrain field, dry-band/wet-grid profiles and water/swamp geometry capture are prepared but ungenerated | Satellite imagery, OSM buildings/facilities, habitat objects, complete water appearance and hazards; complete geography-service behavior |
| Map generation/services | Verified captures drive offline terrain resources; missing runtime resources reject explicitly | Mixed geographic layers, procedural random recipes, authored story arenas, live source preparation/qualification, cache refresh and relay fallback |
| World | Source terrain vertices/topology/portal holes; graded roads, bridge slabs, tunnels, roofs, gallery openings and columns; native Jolt collision | Full scenery, texture/shader appearance, edge geometry, environmental LOS and complete traversal equivalence |
| Movement | Native authority physics and source spawn positions/headings; charged jump, automatic morph launch/landing, lift budgets, hover/altitude bounds, damage-proportional sinking, source shallow/full/frozen immersion, marine tide lift reference and ice floor/ceiling constraints are implemented but unverified | Complete source integration/order, slope support, climbing, complete surface/hazard effects and traversal certification |
| Combat math | Verified RNG, shield overflow, range/falloff, fan/line/blast geometry and target volumes; evasion, suppression, directional defensive shields, critical modifiers and elemental statuses are implemented but unverified | Final source-oracle/integration verification; complete environmental and special-entity interactions |
| Weapons | Authority ammo, reload, fire cadence and native hit queries; source beam/rail instant attacks; source 3D fan body spans, per-bin nearest targets, deterministic ties and building caps; team-vision/LOS gates for direct, fan and line attacks; intentional blast coverage retained; guided/FNF flight with launch spread/climb, guidance distance, fixed laser point, chase fuel, swept proximity and native segment collision; launcher crosshair AA selection; 45-degree ground lob, low-solution charge ladder, terrain clamp and private authority arc preview; flat gun flight with first-body direct hits and terminal planar penetration settlement; hero-only acquisition cone, confirmed-anchor hysteresis, target-dependent launch ranges, quarter-second authority lock checks and in-flight FNF continuation; base missile flight and interception by instant, kinetic and penetrating attacks; source bridge/tunnel/gallery blast-layer separation and rooftop height references; phase/reflect/attraction/report gates and reverse-order skill interception are written but unverified | Complete muzzle/model-centre and reachability envelopes, full status/buff interactions, final missile-defense integration and source-specific reports remain pending |
| Abilities | Source cast channels, squared interruption fractions, independent charges, buffs/heals/auras, EMP/CC, stealth/alpha, rally/revive/recon, interception, reflection, phase exit, shield bash, siege mode, tactical fog, six-panel cube fields, clones, autonomous summons, holograms and point-delivery carrier flight/arrival/interception are implemented but unverified; source scene export/packing and original oracles are prepared | Other special/support fields and full interactions; source carrier/companion model generation, climate and NPC targeting, full skill/body presentation, owner disconnect cleanup and populated transport/render verification; unsupported paths reject before spending resources; final source/integration verification |
| Economy | Eight tracks, source remote/dead purchase eligibility, shared lane creep upgrades, permanent damage assists, bounded score, bounty modifiers, death penalties, scene salvage/cash/ammo/affix loot, timed airdrop rewards, civilian aid and civilian/spy kill credits are implemented but unverified; battery overcharge/charge deadlines and item/skill healing source gates are written | Balance preferences, full shop/campaign eligibility integration and final purchase/death/assist/loot/supply/civilian verification |
| Waves/NPCs | Source compositions, ordered prefill recipes, mirrored spawn jitter/floors, planar progress, wave cohesion, control/push rules, 8 Hz NPC stepping and dual base missile guns; NPC target gates/priorities/cache, captured creep damage/durability, per-target blast settlement and AA-ambush producers are implemented but unverified | Native traversal/support and weather integration, source single-body/mode integration and complete NPC tick/transport verification |
| Camps/civilians | Source camp sampling/rosters, garrison healing/protection, tether/aggro movement, bunker/member respawns, first-clear liberation, civilian/spy seeding, follow/away/wander/aid/death/respawn rules and private spy identity are written; camp obstacle clearance, native G/H interaction and per-ID civilian component geometry/centre/rig assembly are implemented but unverified | Head marks, full geography/building visual clearance and populated render/transport/integration verification; source companion/component resources remain ungenerated |
| Bots | Original four difficulties, global/per-operation APM deadlines, role/policy priorities, threat decay, alert bearings/scope search, bounded turns, PUSH/ENGAGE/RALLY/RETREAT, skill/heavy/buy/guard decisions and native body collision are written; authority direct-fire and heavy report paths share weapon resources | Complete frame-order/traversal/boss/super integration, seeded complete-match comparison and populated transport/render verification; source policy metadata and prepared oracles remain ungenerated |
| Match outcome | Authority core destruction, hero respawn and result screen; source faction kills/deaths/paid assists/weighted creep last hits, public snapshots and native HUD rows are written but unverified | Complete per-body/squad/mode statistical integration, damage/leaderboards and replay parity |
| Networking | Shared solo/ENet/WebSocket authority; lobby registration, roster, start, snapshots, disconnect handling; large snapshots use a separate reliable native channel | PIN/discovery, spectators, reconnect/late join, snapshot bandwidth/loss profiling, mobile/Web export QA, production hosting |
| Visibility | Shared planar team sight and source LOS heights; skill pulses, stealth/blind gates, tactical fog sight/protection and cube-plane LOS are implemented but unverified | Full environmental vision effects, source grazing-obstacle tolerance, event audibility and final status/field visibility verification |
| Story | Source BOSS/siege rules and segmented HUD; six chapters, exact named rosters/difficulty/environment, faction unlock/intro persistence, first-visit prologue, native briefing/pilot/art selection, source crawl/pan/zoom/skip semantics, non-blocking timed radio, authority siege track and victory transcript/replay are written; offline/ENet/WebSocket share campaign room setup; original single-lane map definitions and both base assignments have export/capture/bake paths | Source campaign captures and 24 terrain/road resources remain ungenerated; full scenery/transition VFX, campaign input/render/traversal and lifecycle certification and final source/runtime/transport verification |
| Super battle | Single human third faction, both full Bot teams, all 32 pilots, source 0–100 combat interpolation/extrapolation, shared authority purchase/death recomputation, summon creep scaling, absolute body/collision/aim-centre scale and source FPV eye/forward scale are written; independent respawn sampling, both-base repair, three-faction stats and native shop with default auto purchase are prepared | Source super metadata and third-faction companion/projectile resources remain ungenerated; full body/VFX, deployment preferences, spectators/recovery and combined movement/match/render/transport certification |
| Environment | Source seven-dimensional climate, independent seed, solar/lunar schedules, thermal freeze/thaw history, rain/snow/sand surface state, movement/lift/jump/cadence/reload/cooldown/damage/accuracy effects, probabilistic freeze and entity/scenery lightning/shockwaves are implemented but unverified; native dynamic sky/depth fog/light, precipitation particles and strike flashes; water/swamp classification, marine tides, immersion and proportional frozen-fluid burn; four fire kinds, expiry/quench/DOT and original fire/smoke scene export/animation paths; source hazard/vehicle/mine/AA/relay seeding, lane connectivity, corridor pruning, physical rubble/fire/salvage, flood movement/jumps and mine proximity presentation are written; four seasons/times and eight starting weather choices | Cloud/fog-bank and precipitation detail layers, contact effects, rendered deposits/permanent scorch, complete scenery roster, source damage/cracks/debris, per-entity hazard/fire geometry variation, water waves/shore/underwater appearance and full environmental/render/transport certification |
| Input/UI | Native Chinese lobby/HUD/shop/minimap and weapon advice/glows; native multi-pointer touch sticks/buttons, original tap/hold-fire rules, sensor-backed gyro, persisted look/movement/touch preferences and host-finalized live control modes are written; ZR view-lock/cycling, shared fire/weather scope radius, native ring/fog/blur and source FOV easing are written; source wheel weapon-mode toggle, direct RMB stance-selected cast, arrow/numpad bindings, frozen look/shield gates, empty-heavy fallback, authority recoil/echo input penalties and impulses, private view shake, F shield stance, held jump input, cast countdown, lift, ability charges, civilian G/H prompts, confirmed-lock halos/rings, incoming-lock HUD and private skill-preview rosters, plus source-limited supply/loot/relay/threat/civilian notices are implemented but unverified; minimap excludes source neutral actors | Touch cooldown/portrait presentation, spectator controls and remaining balance/deployment preferences; full source aiming/body integration, siege locks and immediate impact timing, complete combat feed; sensor hardware, HUD/render/transport and source frame-order verification |

## Verification boundary

Static tower/base, camp and autonomous companion body binding is now written,
but remains ungenerated and unverified. Body exports include the actual camp
rosters and `SUMMON_BUILDERS`, plus the source hologram/wingman alias. Native
units share the captured locomotion/combat driver while preserving their existing
authority dimensions, garrison visibility and resource paths. Missing camp or
summon body scenes reject content preparation or casting before spending.
Carrier body binding/attitude and per-ID civilian assembly are written below.
Complete source surface/interpolation integration remains separate work.

Towers retain original world-heading tracking, idle scanning, pitch clamps and
unit-only visual acquisition. Main buildings retain their source orientation
while the two base guns independently remember targets, ease pitch/yaw and
return to the authored resting angle. The original battery builder and placement
method provide its graph and height. Native packing parents the separate source
battery under the body while keeping its world frame and excluding its subtree
from the body's occluder registration. Gameplay silhouette measurements still
precede the battery. Base launches retain their original authority missile
origins, independent cooldowns and spending; they do not add a straight tracer.

NPC target presentation now follows the actual server/client height reports:
ordinary NPC/base reports round aerial target altitude using JavaScript half-tie
semantics, while autonomous companion reports retain fractional altitude. Body
events cache emission-time terrain height for hidden/garrison fallback ports.
The original body-height fallback, explicit air-height override and garrison
slit radius/height have prepared references, including zero horizontal distance.
Each accepted NPC shot retains its own short-lived muzzle origin for later
snapshot tracer presentation; subsequent barrel changes cannot replace it.
Source styled discharges, artillery arc-pitch production and shared impact
effects are now written below. Entity-only clone firing is written below;
complete frame timing still requires certification.

TPS occlusion now registers native MultiMesh batches, queries actual instance
transforms with the shared triangle BVH and includes their bounds in body
sampling. Any intersected instance fades its batch, matching the source mesh
material boundary. Fades isolate the batch/mesh/material bindings; restoring
materials keeps instance animation and respects external material replacement.
Prepared source cases include mixed materials, mirrored/nonuniform instances,
instanced owners, empty batches and moving instance buffers. Native suites also
check shared-resource isolation and animation during fade. Engine precision,
source cached-bound behavior, full raster shaders and render equivalence still
require final certification.

Original static/companion mount and fallback references, live binding checks and
`-Bodies` cases for independent base targets, tower barrels and replay rejection
are prepared. No source/scene generation, compilation, fixture execution, runtime,
render or transport test has run during this implementation.

Primary NPC bodies now share the captured pose pipeline, but remain ungenerated
and unverified. The original `NPC_MODEL_KINDS` roster supplies soldier, APC, tank,
rocketeer, howitzer and helicopter scenes for both factions and Super. Native
binding preserves the source fit instead of rescaling a rest glTF. Wheel/track,
anatomical/gait, rigid recoil and spinner drivers reuse the same native body
passes. NPC altitude is cached on authority/snapshot paths, with zero lift for
ground NPCs, and rendering does not issue a terrain query.

`BodyMountAim` retains independent vehicle turret heading, mechanical pitch
limits, optional arc-pitch override and aircraft shot-memory pitch. It executes
before combat/locomotion on the same accumulated LOD step. Presentation-only
nearest acquisition retains source strict range/tie rules, hidden-self and
neutral/static gates, inclusive quarter-second cache deadlines, stale cached
dead/hidden targets and immediate removal rejection. Existing NPC shot events
now carry presentation identity, target memory, source weapon-style pose slots,
alternating emitters and matching rigid recoil mounts. Duplicate RPC/snapshot
copies cannot advance a port again or settle combat a second time.

Prepared original NPC references execute mount, muzzle, acquisition and rigid
fire helpers; native suites compare complete nodes, cache traces, recoil clocks
and live model binding. `-Bodies` also has an immediate-only NPC fire/replay
case. Static/camp/summon binding and MultiMesh occlusion are written above.
Source NPC facing/interpolation and styled shot/impact effects are written below.
Full render/transport certification remains pending. No content generation,
compilation, oracle or test has run.

Carrier bodies now bind the captured source graph through the same native body
pipeline. All factions retain separate bomber and hypersonic graphs without a
fabricated locomotion rig. Kamikaze escorts retain each pilot's actual forged
chassis, authored rig/morph references and original `SIZE_F` root scale; their
existing authority hit volumes remain unchanged. Content availability checks
the casting pilot's escort scene before spending, rather than one sample pilot.
Heading uses shortest-path easing and hypersonic pitch derives only from each
presented displacement, with the original stationary threshold, snap behavior
and local-axis `YXZ` composition. The remote position/surface driver is written
below; complete frame integration still requires certification. Prepared original-method fixtures cover
heading wraps, vertical flight, stationary frames, threshold edges and snaps,
plus native binding for every exported carrier graph.

Clone shots now use their original entity-only NPC presentation route. They
query the current light emitter immediately and advance the immutable fire event
on the next combat pass; no owner/sibling emitter is advanced by that report.
Both morph trees retain the original deferred sequence update, including several
reports before a render pass. Original `_onEvent` statements now produce clone,
owner and sibling traces; companion tick fixtures also retain the original shot
identity. Native suites check these paths and immediate/snapshot replay rejection.
These changes remain ungenerated and unverified. No generation, compilation,
source fixture execution, runtime, render or transport test has run.

Civilian bodies now assemble original component scenes selected by each actual
entity ID and profession. Offline exports execute the original main, hair,
clothing and profession helpers with neutral geometry proportions and explicit
palette bindings. Runtime GDScript selects native scenes and restores the
original width, shoulder/head proportions, material colours, per-body height
fit, asymmetric centre and team ring. Original torso/pelvis surfaces scale from
their captured source geometry; original articulated limb chains share the
native biped pipeline. Authority collision dimensions remain source body scalars;
visual assembly never consumes the combat RNG or reads private spy identity.

`--civilian-parts` packs the finite component catalog; raw development graphs
are excluded from delivery exports. Missing parts reject content preparation.
Prepared references execute complete original civilian models across all
occupations, seeded wraparound and appearance-category coverage, comparing
world vertices, normals, palettes, silhouette and moving/resting frames. Native
assembly and comparison suites are written but ungenerated and unverified.
Head marks, complete surface/facing frame integration, final shaders and
populated runtime/render/transport certification remain pending. No generation,
compilation or test execution has run.

The prepared `-Bodies` transport scenario now also carries independent clone,
per-pilot kamikaze, rigless hypersonic and per-ID civilian bodies. It checks
replica appearance/chassis binding, deferred clone posing, event replay rejection
and unchanged authority HP/ammo/resources/RNG alongside the existing hero,
static battery and NPC cases. Both transports remain unexecuted.

Remote body presentation now owns an independent native world transform, with
the original horizontal response, shortest-path heading response, strict
movement/stationary threshold and live shot-memory/nearest-enemy priority.
Actor physics, authority hit volumes and resource settlement retain their own
transforms. Offline and network presentation consume the same published snapshot
target, altitude, shield and defensive state, without applying actor interpolation
again or reading newer authority state between snapshots. Fresh snapshot bodies
retain source ground placement and factory heading before their first visual
frame, including emission-time muzzle queries. An unpublished remote body does
not consume its visible event serial early; publication precedes buffered event
delivery. The local owner's initial pose follows the source self branch without
clearing FPV fire history on its first TPS frame. Static bodies retain their world
heading; carrier pitch consumes that same presented displacement. Source NPC
flight classification remains distinct from hero flight/altitude state.

Surface queries use the previous rendered position for LOD, cache the result
between heavy frames, retain exact lift height and keep the source water/deck
clamp for ground NPCs. Flight references take the maximum of terrain, bridge
deck and closed tunnel roof, excluding unrelated obstacle tops. Ground references
reuse the existing continuous-structure and ice rules. Native lane profiles now
march the original paths at source spacing after initial weather setup, retain
their previous standing-height seed and query strict nearest samples in stable
grid order. Facing and turret acquisition share their original target cache.
Mounts, hidden fallback height and locomotion consume the rendered frame.

Prepared original `_updateEnts` slices and `_buildLaneSurf` references cover
near/far LOD, stationary aim expiry, yaw wrapping, snaps, lift changes, deck/water
handling, open/closed roofs, degenerate/short paths and strict radius/tie cases.
Native suites also check that live body interpolation cannot move physics or
spend resources/RNG. These paths are ungenerated and unverified. Source standing
platform/blocker metadata, static pad heights, visibility re-entry lifecycle,
complete snapshot/frame order, populated transport/render and final certification
remain pending. No source generation, compilation or test has run.

NPC shot events now select the original per-weapon style, with base/tower
priority and independent event-kind/actor-weapon fallback ordering. Gun/cannon
layers, compact rockets, wingman beams and eight-chord clipped artillery share
native pooled meshes, billboard stars and MultiMesh energy rings. Artillery
retains the lowest reachable source charge, low-angle velocity, compressed
visual flight time, delayed endpoint spark and analytical derivative facing.
Its handheld compensation or timed mechanical pitch uses that same launch
angle; the original artillery entry retains its default white heat core.
Base launches add their original muzzle star/ring without another projectile.
Immediate body events and snapshot copies share the per-actor presentation
serial and captured emission-time port, so replay cannot allocate more FX or
restart the barrel angle. Effects never settle HP, ammo or damage.

Shared light/heavy muzzle and contact bursts now retain the original nested
crowding gates, colour layers and fade curves. The original explosion primitive
uses one native batch for rising fire beads and radial sparks, retaining its
linear-colour cooling and low-power count. Existing boom snapshots now use one
offline/network presentation entry, including source colour priority and the
strict below-12-metre ground-ring gate. Source geometry and the actual spark
canvas texture have export/packing paths (`--npc-effects`); missing resources
stop rendered match preparation explicitly. A separate visual RNG supplies
sprite roll. The shared list applies original low/normal creation limits and
oldest-first global eviction before reverse-order fading/expiry.

Prepared original-method references cover all style IDs and report overrides,
zero horizontal range, blocked ballistic chords, all source side colours,
delayed/expired stars, zero-sized bursts, nested full-budget paths, explosion
height thresholds and instance matrices/colours. `-Bodies` now also carries a
howitzer, checking its actual barrel pitch and immediate/snapshot FX rejection
without authority resource/RNG changes. All fixtures, scenes and validation
remain ungenerated and unexecuted. Full hero fan/lance/discharge integration,
complete explosion-producer coverage, kamikaze embers, blast camera/contact
reactions, runtime low-power preferences, entity visibility/re-entry lifecycle,
shared budgets across remaining effects, final fog/toon/curve shaders and
populated runtime/render/transport certification remain pending.

Hero fan and lance presentation now has original asset export and native scene
drivers, but remains ungenerated and unverified. Normalized discharge shapes
retain their complete source triangle topology, material colours and per-slot
opacity envelope. A full-radius low-opacity channel exposes the actual shared
penetration cylinder, while styled cores and payloads keep their original scale,
zero-age projectile pulse and bounded travel time. Charged beam release delays
only the original release entries; its full-width channel remains immediate.
Initial authored meshes retain factory scale/opacity until the first fade pass.

Native fan ArrayMesh instances derive every vertex from original source
coordinates and ownership bins, with source azimuth/elevation clamps, strict
shared-edge neighbouring-range limits and obstacle-only ray clipping. Each
vertex retains its bin in an unused UV channel; a native vertex shader computes
the original travelling brightness before interpolation. The clipped cone
therefore remains stationary throughout a sweep. Mesh instances own their live
geometry and materials; pooled authored groups share one retained-count cap
derived from the original global FX budget.

Instant human fan/line shot snapshots and bot plasma reports now use this shared
presentation list. Local effects retain their firing level and immutable launch
port; remote presentation resolves its source level-one definition and current
rendered emitter. Scene preparation rejects missing packed resources. Prepared
`--weapon-effects` graphs include source-normalized beam/bullet/ion families,
fan ownership metadata and the exact lance payload variants; raw graphs are
excluded from delivery exports. Original helper fixtures cover all actual
fan/line pilots and both weapon slots at levels one/four, vertical/zero aiming,
obstacle clipping, crowded/full lists, delayed release and expired envelopes.
Native suites compare complete vertices/indices, material/transform clocks,
per-vertex brightness ownership and production event resource/RNG isolation.
No generation, compilation, source oracle, runtime, render or transport test has
run. Owner physical terminal discharges and remote launch/burst routing are
written below. Remaining muzzle/impact reactions, low-power
preferences and populated frame-order/render/transport certification remain.

Owner kinetic penetration now emits a distinct authority terminal presentation
after its flight ends, retaining the original launch port and final endpoint.
The event never repeats penetration settlement or a launch muzzle burst. Local
authority presentation, immediate native RPC delivery and buffered snapshots use
the same receiver. Its per-actor transport serial follows completion order,
rather than launch order, so a slower earlier round can still finish after a
newer one. Duplicate copies cannot allocate another channel or payload.

Terminal notifications immediately retire their owner visual mesh. A timestamped
guard rejects pre-impact and same-clock snapshot copies until a strictly newer
authority publication omits that visual ID; old snapshots cannot resurrect the
model while the reliable event and snapshot channels catch up. No generated
snapshot or renderer state chooses the impact location or damage budget.

Pure visual shells now preserve the original factory's zero-age/zero-speed tail
pose until their first flight step. A genuine static/terrain collision produces
the original contact star through the shared effect list; reaching the target
range without collision only recycles the shell. Owner projectile snapshots
transport the source fixed FX speed separately from their changing gravity
velocity, including launcher AA speed, while visual shells retain actual flight
speed for their own age/speed animation.

Prepared original kinetic traces now record the actual `_lanceVisual` call, and
original visual-flight traces retain contact-star coordinates/radius/colour.
Native suites cover production terminal consumption, resource/RNG isolation,
replay rejection, completion after a newer launch, same-clock/older snapshot
guards, initial factory poses and actual mesh/pool/contact lifecycle. These
paths remain ungenerated and unverified. Other terminal feedback,
full frame integration and populated runtime/render/transport certification
remain pending. No source generation, compilation, oracle or test has run.

Remote human relays and bot reports now dispatch through the source level-one
weapon definition: clipped penetration channels, ballistic/guided visual shells
or honest-contact straight shots. Physical launches relay the original short
direction endpoint; lob launches retain their fire-control aim and JavaScript
rounded speed. Physical segment telemetry no longer creates duplicate straight
tracers. Public bot poses follow actual report cadence while private authority
poses retain every paid attack.

Remote compressed bursts share the existing visual-only reverse-order queue.
Each callback re-queries the current nearest same-pilot muzzle, including squad
clones; the initial report consumes its immutable pre-fire port. Owner fire poses
propagate to observed squad rigs once, while entity-only clone shots retain their
separate route. Surviving clones retain the canonical pilot identity after the
main body leaves view. Missing callback bodies retain the source aim fallback.
An initial report without an observed shooter uses source fallback coordinates
and immediate primitives; it cannot infer a weapon definition or queue a burst.
Unbound plasma reports retain the source procedural fan rather than disappearing.
Transport serials reject immediate/snapshot duplicates, including plasma reports,
without advancing resource, damage or combat RNG state.

Local fan and remote plasma entry points now preserve original procedural
fallbacks, including their distinct central-range factors, blade counts,
vertical spread, wall clipping and barrel variants. Authored effects still take
priority. Native MultiMesh instances render original ion coils and seven static
discharge arcs around the captured throat geometry; low-power counts, source
lifetimes, colour assignments and fade curves are retained. The source lance
entry point also retains its missing-asset beam and kinetic fallback primitives.
Visual scatter uses the existing independent presentation RNG.

Prepared original-method fixtures cover report dispatch, muzzle selection,
launch relays, moving/removed shooter callbacks, fan fallback primitive/query
ordering and authored/procedural ion transforms. Native suites include live
owner/clone port identity, plasma replay and resource isolation; `-Bodies` now
has an immediate remote report plus snapshot-replay case for ENet/WebSocket.
All these paths remain ungenerated, uncompiled and unverified. Remaining terminal
feedback, visibility/re-entry, global frame order, low-power preferences and
populated runtime/render/transport certification are still pending.

Original fire/smoke sprite textures now have offline capture/export paths.
Native pooled billboard quads share the curved-world camera projection, with
additive fire and normal alpha-blended smoke. Source ember, crash-smoke and
death-plume producers retain random draw order, velocity, size, lifetime and
delayed visibility. Gravity and drift integrate the actual frame delta rather
than an analytic trajectory; plume smoke delay retains its original normalized
life-fraction gate. Source fire/smoke prewarm and retained-pool caps are exported,
and these sprites participate in the existing oldest-first global FX limit.
Kamikaze boom presentation now includes the original twelve-ember burst.

Published victim HP/shield changes now drive world contact effects through the
same observer path offline and on replicas. First observations, healing and
duplicate snapshots do not produce a hit. Defending heroes with remaining shield
and a shield drop use the source shield-contact branch even when HP also drops;
other armor losses retain original stars, embers and smoke, including the larger
base/tower variants and camera-distance compensation. Hidden/removed observers
discard their previous baseline. Presentation reads current rendered positions
and captured body dimensions without changing authority state.

Body exports capture the exact guard material selected at entity spawn. Shield
hits preserve the original maximum-flash rule on that material, including morph
bodies, instead of redirecting the contact to whichever form is currently active.
Prepared references execute original sprite pools/producers/effect ticks,
snapshot branch statements, victim helpers and actual authored guard callbacks.
Native suites cover zero/hitched frames, delayed smoke, overflow/recycling,
repeated snapshots, shield/armor priority and combat-resource/RNG isolation.
These paths remain ungenerated, uncompiled and unverified. Remaining private
damage response, death sequences, non-rig scenery damage, blast reactions,
remaining effect producers and populated render/transport certification remain.

Original first-person camera shields now have separate native scene packing via
`--first-person-shields`. Exports execute the actual constructor setup and retain
the six-sided plane, camera-local placement, per-character pattern, planar shader
parameters and source flags. Runtime ownership remains separate from cockpit
visibility/recoil. Source FPV/TPS, defending, remaining-shield, death and defense
cast gates are written, with horizontal expansion and shader stepping while
hidden. Changing character styles retains the live flash peak and time; scene
instances isolate their mutable materials. Missing packed camera shields reject
rendered match preparation, and raw graph files stay out of delivery exports.

Private observed vitality now retains the original half-point loss threshold,
shield-versus-armor branch and amplified shield peak. First observations,
healing, death and view resets do not produce private feedback; the world-contact
branch remains independent. Armor loss emits a local presentation signal that
drives a native red edge vignette below the HUD and above the scope mask. Its
gradient/anchors/duration come from source CSS, with browser ease-out keyframe
interpolation and the original active-animation/restart guard. No presentation
receiver can apply authoritative sinking or damage again.

Prepared original references cover constructor geometry/materials, all pilot
styles, active/hidden shield clocks, cast boundaries, style retargets, private
snapshot gates and actual browser-computed hurt opacity. Native suites compare
packed topology, material isolation, repeated-hit admission, camera ownership
and live snapshot resource/RNG isolation. These additions remain ungenerated,
uncompiled and unverified. Blood, hitstop, death/scenery/blast reactions,
remaining effect producers and populated runtime/render/transport certification
are still pending.

Blood/glint event and state foundations are now written but remain ungenerated
and unverified. The authority accumulates actual shield-plus-armor loss per
primary pilot and attacker, retaining the first source position/optional human
eye height until the shared eight-Hz publication. Native publication preserves
source decimetre rounding, pilot/source ordering and one flush for all peers;
clone/NPC victim and environmental bearings do not invent a cockpit splat.
Existing immediate hurt telemetry retains its separate consumers.

The native glass-residue state executes source dose curves, camera-space bearing
and optional elevation, FOV/aspect-dependent inset clamps, immutable main/satellite
drops, distinct blood/glint radii and lifetimes, separate oldest-first caps and
one shared monotonic spray identity. Private visual randomness does not consume
combat RNG. Source fade/expiry/final-empty-report/clear behavior is written, with
prepared original authority/client method fixtures and native resource checks.
Native overlay binding/compositing and replay/lifecycle cases are written below.
Pixel/filter, full frame-order and populated transport certification remain
pending. No generation, compilation, source oracle or test has run.

Blood/glint overlays now receive published authority bearings through the shared
world-event receiver. Only the local primary pilot consumes them; serials reject
snapshot replay. View changes, death/respawn and room reset clear both layers,
while a new room resets only the publication replay guard. Glass IDs retain
their initial percentage position and drop geometry; later reports update only
the source-rounded opacity. Binary-aware bounded decimal serialization matches
JavaScript `toFixed`, including negative values and decimal half-ties.

Original DOM callbacks/CSS now export the two gradient palettes, stop positions,
canvas extents, blur and drop-shadow parameters. Native per-splat SubViewport
chains draw first-layer-on-top radial gradients, filter premultiplied colour,
composite the alpha shadow underneath and apply group opacity afterwards. Static
stains render once at creation or viewport-size change, with retained tile reuse;
fade frames only change opacity. Native layers retain source blood/glint order
and fullscreen clipping, below HUD controls and above the hurt/scope masks.

Prepared source DOM fixtures cover immutable ID reconciliation, CSS decimals and
opacity. Deferred browser raster capture records blood, glint and overlapping
layers in landscape/portrait viewports. `tests/splat_render.tscn` compares native
GPU output against those source PNGs in premultiplied space and writes mismatch
images to `build/splat_render`; it requires a rendered session. Native suites
also cover pipeline reuse/retirement, resize invariants, local-only consumption,
duplicate publications and view/room clears. `-Bodies` now includes actual
merged same-attacker bearings in its snapshot stream and checks spray replay.
All additions remain ungenerated, uncompiled and unverified. Source pixel/filter
acceptance, global frame timing, populated render/ENet/WebSocket certification,
death/scenery/blast reactions and remaining producers are still pending.

Source hitstop and capped presentation frames are now written but unverified.
The native frame clock spends the previous stop budget before applying queued
death reports, retains the source signed remainder and freezes the complete
crossing frame. New reports extend a stop by maximum duration rather than adding
time. Death-kind durations and physical scenery exclusions come from executing
the original death-event statements offline. Authority simulation and absolute
presentation clocks continue; no engine-wide time scaling or pause is used.
Touch/stick/numpad look, view easing, body interpolation, cockpit/shield updates,
glass lifetimes and shared projectile/effect stepping use the capped frame delta.
Zero-delta body frames still apply source snap, terrain and LOD bookkeeping;
combat and locomotion retain their original minimum-step guards.

Ordinary lethal settlement now publishes the missing source death event.
Existing civilian/clone/slab/third removal paths use the same serial allocator
without double publication. Death reports survive actor removal and fog filtering,
as in the original snapshot path. Room-local serials reject repeated snapshots.
Prepared original frame traces cover overlap, zero time, long frames, signed
remainders, civilians, heroes and scenery; authority fixtures cover normal death
reports and visibility-independent publication. `-Bodies` carries a death report
through the regular snapshot stream and checks replay. Blast feedback and complete frame-order integration
remain pending. No generation, compilation, oracle or test has run.

Death-event mechanical debris and comic pops are now written but unverified.
Offline capture exports the original four chunk geometries/material properties,
linear chunk palette and original Canvas-rendered death comic textures. Native
MultiMesh batches preserve the source low-power shape/count split, radial launch
and seven random samples per chunk, semi-implicit gravity, floor bounce,
per-axis spin and final-30-percent shrink. Retained bursts keep private material
and instance buffers. Comics retain source word selection, random roll, initial
scale, overshoot/fade and the source pool's free-stack cap. Comics still admit
while ordinary effects are crowded; the shared global cap retires oldest first.

Original death-event statements now export ordered producer plans with exact
terrain-based offsets, large-body/hero gates, faction accents, civilian handling
and physical scenery exclusions. Shared native publication presents those plans
for already removed actors and rejects replay before allocating effects or
renewing hitstop. Explosion calls reuse the existing source-derived native
burst; comic and mechanical debris use their dedicated producers. Blast requests
are retained in the source plan and emitted as presentation signals; authority
body impulse and camera trauma consumers remain pending. Full toon/curve shader
appearance, other comic producers, collapse feedback and final
source/GPU/transport acceptance remain pending. Prepared fixtures exercise all
four words, optional/black accents, both quality modes, bounce/shrink, zero and
long frame steps, crowding/overflow, producer ordering, all faction colours and
publication replay without consuming combat RNG. No generation, compilation,
oracle or test has run.

Carrier interception reports now also come from the original lethal-settlement
oracle. Native point-delivery decoys no longer add a fabricated blast when shot
down; kami/hyper fracture reports retain the original radius and SAM flag. The
ordinary death report remains first, without delivering the cancelled ability
budget or adding damage. Carrier resource readiness requires the captured report
table before casting. Prepared interception fixtures compare report order and
flags alongside the existing bounty, score and cancellation assertions. These
changes remain ungenerated and unverified.

Death cinematics are now written but unverified. A presentation-only state
machine retains the last live eye/body/velocity and source view angles, ground
shake/topple/sink, minimum camera height, airborne adaptive gravity and drag,
per-axis tumbling, separate surface probes, ground contact versus in-air timeout,
bounded impact hold and one-shot climax/cut. Zero-delta frames retain the source
ground-shake sampling; smoke and engulf accumulators keep their original strict
versus inclusive deadlines. Synchronous effect callbacks share the existing
private visual RNG, including source fire/smoke side bands and lateral embers.
Climax requests extend the presentation stop without pausing authority time.

Local lifecycle handling owns Camera3D in world space while dead, preventing
snapshot interpolation, physics sync and input FOV writes from replacing the
cinematic or its final view. Respawn, primary-pilot replacement and room exit
release that ownership. Owner velocity is carried once per private snapshot,
without adding velocity to every public unit. Both publication paths initialize
the local cinematic before dispatching world death effects, matching source
producer order. FPV cockpits remain visible during the transition; respawn
countdown notices wait for its completion and the following publication. The
source default disabled-wipe path finishes synchronously; configurable post
processing/wipe integration remains pending.

The original death CSS supplies red-rim blur/spread/colour, independent infinite
pulse and retriggered whiteout timing. Native overlay passes bake an inset mask
and separable blur only at resize, then animate opacity using wall time. Alert
reaffirmation preserves pulse phase; finishing hides the rim while an existing
whiteout finishes. Canvas layers keep the rim below HUD and whiteout above
countdown/HUD/menu but below shop. Exact browser filter raster and resize cost
remain unverified. Deferred browser PNG capture and `tests/death_render.tscn`
provide a strict GPU comparison gate; mismatch images go to `build/death_render`.
Glass/death raster gates share one premultiplied comparison/diagnostic utility.

Prepared original-method fixtures cover low/high death heights, zero/long frames,
surface clamps, sloped support, aerial timeout, complete ordered effects, deferred
cut guards and early respawn. Native suites cover CSS easing, phase retention,
camera ownership, room clears and combat-resource isolation. The `-Deaths`
transport case uses real lethal authority damage, early respawn, flying launch
velocity, repeated dead publications, held final view and post-cinematic respawn
over both ENet and WebSocket. Full TPS death-body presentation, configurable
postprocess transitions, remaining blast producers, source pixel/performance acceptance and
final runtime/transport certification remain pending. No generation, compilation,
oracle or test has run.

Blast feedback is now written but unverified. The original client method supplies
camera-distance trauma, body-centre falloff, close-centre backward direction,
ground lift and airborne impulse references. Native authority settlement keeps
ground horizontal impulse separate from vertical lift, excludes dead/no-side and
non-primary actors, and does not spend resources or consume combat RNG. Death,
mine, missile, interception, reflection and ordinary boom reports share the same
publication queue. Reports remain globally visible through fog and entity removal.

Player projectile impacts retain the source's two distinct triggers: immediate
owner-only local feedback and the later global boom. Local impact points use
closed-tunnel floors; global reports retain terrain-relative height. Reliable
owner events carry private recoil state; local/global presentation watermarks
reject RPC/snapshot replay, and older snapshots cannot rewind newer blast recoil.
Both paths use canonical authority camera/body positions rather than client-owned
motion. Full source packet-time and movement integration remains uncertified.

Prepared fixtures execute the actual source blast method, boom callback, local
projectile impact seam and missile report producers. Native cases cover falloff
boundaries, tunnel points, default radii, grounded/airborne accumulation, private
delivery, fog visibility, ordering and resource isolation. The `-Blasts` transport
case checks the original two-trigger sequence over ENet and WebSocket. Legacy
decoy bombing remains unavailable: the original current launch path uses
point-delivery effects rather than the retired bomb producer. Other outstanding
producers and complete frame-order acceptance remain pending. No generation,
compilation, oracle or test has run.

Carrier completion now captures original boom radius/flags and event order from
actual kamikaze, bomber and hypersonic ticks. Native completion publishes the
boom before delivery effects, preserving ordering when delivery itself kills an
actor. Bomber mission completion uses the original SAM fracture; kamikaze and
hypersonic arrivals retain their original flags. Timeout does not invent extra
bomber deliveries. Deferred fixtures cover each motion step, event-time points,
completion reports, ordered deliveries and removal. Missing captured completion
metadata rejects a carrier cast before spending. These changes are ungenerated
and unverified.

Physical scenery collapse now uses the shared effect clock and global oldest-first
budget instead of an independent Tween. Source controller expiry and eviction
both finish the deterministic pose; zero-delta/hitstop frames preserve it. Weak
target references tolerate removal during animation, and a per-instance guard
prevents repeated snapshots from compounding the squash or restarting debris.
Initial collapsed snapshots and dedicated authority bodies take the final pose
without allocating transient effects.

Original `sceneDamageProfile` data supplies burst colours, while actual
`sceneDamageBurst` calls supply seeded chunk/shock fixtures. Chunk randomness is
isolated by entity ID/stage, including JavaScript Number-to-uint32 conversion;
neither combat RNG nor the ordinary visual stream advances. Captured hazard
dimensions determine burst centres and ring radii. Prepared normal/low-power,
unknown-profile, large-ID, clock, eviction and authority/replica cases remain
unexecuted. Static geometry deformation and observed damage bands are written
below; articulated/mobile damage and complete scenery producers remain pending.
No generation, compilation or tests have run.

Static scenery/building damage now has unverified native private ArrayMesh and
material bindings. Original vertices/colours remain immutable across repeated
damage, collapse and repair. Source geometry IDs retain one deformation pass
for shared hull/shell geometry; neutral models preserve resource aliases inside
their own instance while imported meshes/materials remain read-only. Original
full geometry indices survive material-group splitting, so deformed normals and
surface-face selection retain their source inputs. Non-indexed faces, mirrored
bindings, excluded team/weather nodes and multi-material meshes have deferred
original-method fixtures.

Native line meshes retain source crack face limits, area/upward-normal gates,
stable tie order, barycentric segments and repair visibility. Published static
health uses inclusive source thresholds and emits one burst for the observed
destination band, including skipped bands. Initial appearance and visibility
re-entry establish a baseline without replaying damage bursts. Shared authority
and replica receivers retain ordinary victim-contact-before-stage-burst order
(hero ordering is implemented below), and physical
scenery contacts now use captured dimensions even without a body rig. Geometry
updates do not alter collision, health, ammunition, time or combat RNG.

The new exporter executes actual `applySceneDamage`, `sceneDamageStage` and the
original snapshot damage block; prepared suites compare complete vertex/normal,
linear-colour and scar buffers, alias isolation, healing, repeated observations,
fog re-entry and publication order. Native/source transform precision, stable
face-order raster acceptance and performance remain unverified. Articulated/mobile
scars are written below; persistent damage smoke/fire, map-building part-motion pause, removal
dissolve and remaining geography/scenery bindings are still pending. No source
generation, compilation, oracle, runtime, render or transport test has run.

Mobile damage now has an unverified native material/scar implementation. Opaque
coloured materials share private copies inside one body; transparent, no-paint,
outline, team-ring and weather bindings retain their source exclusions. Skinned
and material-array parts still receive eligible tint but cannot receive local
scars. The original first twelve eligible parts, indexed/non-indexed stride,
normal offset, three barycentric control points, stage opacity and light-stage
half-buffer range drive native line meshes parented to each articulated part.
Shared vertices, skinning inputs and animated instance buffers remain untouched.

Original mesh and material bindings are restored on release. Releasing an intact
body does not invent an allocated-damage state; releasing a previously damaged
body permits later rebinding. Authority visibility loss releases private scars
and establishes a fresh baseline on re-entry. Healing hides existing scars, while
a lethal hero snapshot retains the original stage-three reaction. Hero damage
bursts precede shield/armour contact; ordinary bodies retain the inverse source
ordering. Both paths remain presentation-only and share the normal offline,
authority-view and replica publication receivers.

Mesh capture now records source material-array/skinned flags and omits groups
whose array material is absent. Static and mobile damage cache the original mesh
roster even at intact stage zero; later transient meshes cannot become damage
geometry. Deferred source fixtures execute actual mobile apply/release methods
on mixed opaque/transparent, grouped, skinned, excluded and instanced parts, plus
joint motion, healing, release/rebind and the eligible-part cap. Native fixtures
also cover authority visibility, removed parts and combat-resource isolation.
These changes remain ungenerated, uncompiled and unexecuted. Full toon/line raster,
dynamic geometry/material interactions,
removal dissolve and populated render/transport acceptance remain pending.

Persistent low-health smoke/fire is now written but unverified. Native retained
groups reproduce the original smoke sprites, independently randomized dark/hot
crack planes, authored flame meshes and additive embers. Offline capture supplies
the actual smoke/crack Canvas PNGs and unscaled flame geometry; runtime scales
private mesh arrays rather than replacing the authored flame with a cone. Hidden
fire/crack components retain their constructor draws and state. These groups are
owned by their bodies, outside the source's transient global FX budget.

Observed stage admission retains source self/civilian/decoy/kamikaze exclusions,
neutral-profile and collapsed guards, inclusive fractional thresholds, dimension
fallbacks, dead-body clear and invalid-maximum retention. Stage switches reuse
one group; healing, authority visibility loss and collapse release it. Shared
offline/authority-view/replica publication creates groups after contact and
geometry reactions. Visible bodies advance smoke/ember phases on capped,
hitstop-aware presentation delta, while flame/hot-crack flicker uses wall time.
Garrison/hidden bodies retain their phases. Wind drift is transformed through
the body's world rotation, including mirrored/nonuniform source frames.

Deferred fixtures execute the actual `makeDamageFx` constructor/update closures
and `_updateDamageStage` method. They cover random draw order, every child pose,
colour/opacity, authored flame buffers, phase wrapping, stage retention, wind
clamps, mirrored parents, zero-delta frames, profile flags, non-finite health and
allocation/clear/recreate lifecycle. Native cases also cover visibility release
and combat-resource isolation. Shader crack bias retains original factor/units
and captured WebGL depth precision, using Godot fragment `DEPTH`; exact GPU bias,
transparency ordering, toon/curve appearance and performance remain uncertified.
The depth implementation follows the [Godot spatial shader contract](https://docs.godotengine.org/en/4.4/tutorials/shaders/shader_reference/spatial_shader.html)
and [OpenGL polygon-offset definition](https://wikis.khronos.org/opengl/GLAPI/glPolygonOffset).
Scenery part-motion pause, removal dissolve and combined
render/transport acceptance remain pending. No generation, compilation, oracle,
runtime, render or transport test has run.

Known non-neutral body removal now has an unverified presentation-only retirement
path. Native actor deletion detaches the last rendered model before freeing its
colliders and gameplay node. Only previously observed actors qualify; the same
publication's die/moon-boom IDs authorize stage-three geometry, one seeded burst
and the original shared-effect lifetime. Silent removals dispose the retained
model without inventing debris. Static bodies use the source quadratic Y squash;
mobile bodies use its linear squash. The original removal method supplies the
duration and floor scales, rather than introducing native balance constants.

Persistent damage FX freeze and hide during retirement. Native animation players
stop with their current pose, and occlusion/target/range-glow registrations leave
before the model becomes independent. Ordinary body effects share global
oldest-first eviction and expiry, retaining private source resources and both
combat RNG streams. Deferred original-method fixtures cover visible/hidden,
mobile/static, silent/death, zero-delta, eviction and repeated publication paths
for both authority and replica presentation. Shader dissolve is written below;
full part-motion lifecycle, exact authority pre-publication animation
timing and combined render/transport acceptance remain pending. No generation,
compilation, oracle, runtime, render or transport test has run.

Material-gated removal dissolve is now written but unverified. Remaining removal
paths retain the source visibility, positive-duration and supported-material
gates. Intact neutral views request one destination burst; collapsed neutral
views do not. The source civilian renderer is not neutral even though civilian
gameplay is, so its generated component materials retain the normal source
dissolve flags instead of taking the obstacle branch. Unsupported material trees
and silent/fog removals disappear immediately. These decisions never add generic
damage, fabricated shapes or new authority state.

Offline capture takes the actual celHash/celNoise/celDissolve GLSL functions from
the source material compile hook. Native ShaderMaterial uses those saved
functions, world positions before curvature, the removal-time origin and original
smoothstep-out clock. Opaque surfaces use discard without entering the alpha
pipeline, following the [Godot spatial shader contract](https://docs.godotengine.org/en/4.4/tutorials/shaders/shader_reference/spatial_shader.html).
Private bindings preserve material aliases, native base colour/texture, emission,
roughness/metallic, vertex colours, alpha-test metadata and cull/depth settings;
outline shells hide while progress is below one. Imported material-slot metadata
retains source counting even across grouped or unused array slots. Release
restores owned bindings and retains changed MultiMesh instance buffers.

Dissolve ghosts advance in reverse order before missile/damage FX, outside the
global transient effect budget, and own no actor/collider/target entry. Prepared
fixtures execute actual setDissolve and removal/ghost methods for clamping,
optional anchors, aliases, grouped slots, instancing, visible/hidden and patched/
unpatched materials, collapsed/intact neutrals, civilians, silent/death paths,
zero-delta clocks and repeat guards. Full toon/outline/weather/shadow appearance,
GPU discard/raster equivalence, dynamic material replacement during dissolve,
part-motion and populated render/transport certification remain pending.
Distance dissolve remains explicitly unavailable if the source enables its
currently disabled FAR_M setting before DOF integration. No resource generation,
compilation, oracle, runtime, render or transport test has run.

Snapshot missile presentation is now written but unverified. Native collision
bodies retain their authority poses and original triangle shapes; a separate
Node3D view uses the actual standalone source projectile scene, source scale and
initial bounds. Published source-terrain-relative targets retain previous target
positions, exponential render interpolation, the squared heading gate, zero-delta
orientation, presentation age and fixed-speed jet animation. Legacy collision
meshes no longer double-render the missile. The interpolated missile query is
written below; complete owner intent/report integration remains a separate task.

Observed missile HP shares the mobile tint/scar and persistent smoke/fire
implementations, including finite-HP/positive-maximum admission and retained
state on skipped observations. Persistent groups now share one binding lifecycle
with ordinary bodies. Removing a view fractures it only for a matching source
missile blast/intercept report; reflection lacks the original missileId and silent
TTL/target loss do not invent debris. Fracture uses the last interpolated anchor
before releasing the view, after normal world event playback. Repeated
removal packets cannot renew a retired view or fracture it twice.

Original missile smoke uses captured low-poly sphere geometry, normal blending,
depth writing, strict accumulator deadline, single-puff reset, shared FX expiry
and scalar expansion/fade. It bypasses ordinary admission limits, as in the
source, while native retained nodes remain bounded by the shared free-node cap.
No new gameplay collisions or impulse settlements come from these views/effects.

Prepared fixtures execute actual `_syncMissiles`, `_updateMissiles` and global
effect ticks, covering repeated snapshots, both heading branches, zero-delta
orientation, jet animation, HP bands/non-finite skips, source removal-ID gates,
silent/impact/intercept/deflection cases and puff expiry. Native cases preserve
a separate live collision/flight sentinel, combat RNG and IDs, and check private
view setup -> world events -> missile fracture order, derived from actual
snapshot method seams. Source graph/metadata and fixtures
remain ungenerated and unexecuted. Full frame/packet queue timing, interpolated
owner aiming, shader/raster performance and combined transport acceptance remain
pending; no generation, compilation or tests have run.

Interpolated missile triangle queries are now written but unverified. Offline
capture retains all source mesh triangles and material sides, including outline
shells omitted from the visible projectile scene. Each part follows its captured
live animation node, so jet poses and render interpolation determine the visual
intersection. Source six-metre broad-phase gates, exact-zero triangle tests,
near/far admission, nearest selection and insertion-order ties are retained.
Hidden or transparent mesh children still participate, as in the source;
persistent smoke/ember sprites do not, while damage crack/flame meshes do.

Native FPV echo shells now compare these visual hits with environmental stops;
terrain wins equal distances and penetrating shells skip missiles. These queries
read no authority missile flight/HP and cannot settle damage or bounty. Native
missile colliders continue to serve authority gameplay. Minimap markers now read
the same interpolated views each render frame, using captured source colour and
dimensions instead of raw snapshot positions.

Deferred fixtures execute actual _rayCandidates and Three.js mesh raycasts over
healthy/light/heavy damage, animated snapshots, hidden roots, duplicate/tied
missiles, inside/near/far rays and broad-phase boundaries. Native cases preserve a
separate live physical sentinel, identity, authority time and both RNG streams;
additional shell cases cover penetration and relative terrain/missile ordering.
Full owner crosshair/intent transport and settlement validation, ordinary unit
mesh queries, source cached-matrix/frame timing, native precision at grazing
boundaries and populated render/transport certification remain pending. No
generation, compilation, oracle, runtime, render or transport test has run.

Owner TPS now has native input, persisted mode selection, camera/body heading
separation, visibility/occlusion updates and authority muzzle/preview routing.
These paths are written but ungenerated and unverified. A hidden body is created
for every human pilot at authority spawn, retaining FPV fire/echo/spinner history;
render cadence, distance LOD and local posing cannot choose its launch port.
Replicas receive physical heading separately from camera heading. Directional
defense, companion offsets and carrier orientation read the physical heading.

The last scoped heavy round selects the restored TPS body port while preserving
the preceding FPV camera ray, matching original `_tryFire` ordering. Its single
resource spend, recoil direction, trajectory origin and lob-cache invalidation
use that selected pose. Immediate owner feedback restores TPS; request and clock
guards stop an older scoped snapshot from undoing that transition. Original
empty-heavy/mode and placement methods now have prepared source traces. Authority
and local preferences use consistent reentrant notifications, without releasing
held controls during the temporary scope switch. Native respawns transport a
camera-reset generation and reset body heading and source-derived pitch; revived
authority bodies also clear old pose clocks. Complete death/revival camera
cinematics and placement/frame-order certification remain pending.

Owner cockpit scheduling advances its body on each local echo. Public self-echo
events consume transport identity without advancing it again; remote and private
authority bodies advance on those events. All paths retain a single combat round.
Body FX use a monotonic presentation clock anchored once to the authority clock;
subsequent snapshots cannot jitter their ages. Gameplay deadlines retain match
time. Prepared `-Tps` ENet/WebSocket cases isolate ordinary mode/heading transport,
source ring framing, unchanged mode-switch resources, private last-heavy muzzle,
immediate-only feedback and stale snapshot rejection. Existing transport fixtures
explicitly select FPV. No fixture, generation, compilation or test has run.

Body tactical events now use a dedicated reliable native channel, with the
same visibility gate and serial deduplication as snapshot delivery. Charge/
weapon/cast notifications no longer wait for the 8 Hz snapshot timer; snapshots
retain them for actors not yet created when an immediate event arrives. Native
steady/rail gate entry, cancellation, completion and held-fire release now drive
the original idempotent charge-on/off latch without spending resources. Prepared
control oracles execute original `_setRailCharge` alongside original gate blocks.
The populated `-Bodies` transport fixture removes its fixture events from the
snapshot buffer, so it must receive the separate native event RPC before testing
replay rejection, morph and defense. These paths remain unexecuted. No generation,
compilation, source-fixture or transport test has run during implementation.

Private authority-body posing and TPS launch convergence are written but
unverified. `AuthorityBodyPose` owns a hidden, independent captured rig with an
explicit world frame and the same composed locomotion/combat/morph pipeline.
Its simulation caller supplies the aligned presentation clock; render cadence,
distance LOD and client pose changes cannot select its muzzle. FPV retains
the prior skeleton heading and pose, updates the displacement baseline, and
continues spinners; TPS resumes from that baseline. Owner defense presentation
still uses the original local visual gates. Human authority spawn creates the
private graph and accepted shots, fire control and advisory origins use its port.

`BodyLaunchPose` selects the active rig's next non-FX-only emitter and preserves
the source eye/forward fallback when that marker is unavailable. Optional
directions converge on the original camera-ray point, including zero/negative
reach and zero-length normalization. The fallback distance is exported from
the original `_selfMuzzle` method. Prepared source frames now query that method
after complete animated body poses, with both weapon slots, missing/FX-only
markers and changing morph owners. Separate owner-frame traces include FPV
freezes and TPS resumption; native private-rig suites compare all nodes and
shader clocks. No generation, compilation or test execution has run. TPS
selection, aim/body transport and private-rig settlement/preview binding are
written above; complete rendered and frame-order equivalence remains pending.

Captured hero bodies are now bound to `BattleUnit` and the native presentation
frame, but remain ungenerated and unverified. Heroes load their original faction/
pilot body scene, retain its authored fit and +Z facing convention under the
native actor transform, and use `BodyPresentation` for the composed pose driver.
Physics-owned displacement/yaw are supplied explicitly for gait sampling;
visual posing cannot move the authority actor or change its aim frame. Local
FPV bodies remain hidden, while rotors keep their separate per-frame clock.
Fresh FPV owners retain the original builder heading until their first TPS pose;
authority initialization and rendered wrappers preserve that frozen world frame.
Prepared owner traces now start in FPV, fire while hidden and query restored TPS
ports before a TPS pose has run, as well as covering later FPV/TPS switches.
Relative hero altitude is sampled on authority physics/snapshot paths and sent
as `hero_y`; rendering reads that value without issuing physics height queries.
Missing body content reports unavailable content instead of substituting geometry.
Primary NPC glTF replacement and owner TPS/muzzle binding are written above;
companion/static body replacement and final certification remain pending.

Accepted weapon/cast events carry a monotonic presentation-only serial shared by
offline, ENet and WebSocket sessions. Host delivery and snapshot delivery use the
same event consumer; duplicate/stale serials cannot advance morph emitters again,
while distinct same-time shots still advance. Receipt clocks retain source
presentation timing on a shared local monotonic clock, immediate weapon/payload reparenting, heavy release and
source cast-direction gates. Charge-event consumption and original steady/rail
gate producers are written; complete combined weapon integration remains pending.
Revived/respawned replicas snap to their reported position and clear old
locomotion/combat events on the next rendered frame; emitter identity and
transport deduplication remain intact. Far bodies preserve original squared
distance bands, UTF-16 staggering and accumulated heavy-update time. Native
actor interpolation is still used and is not certified as source interpolation.
Snapshot correction and match-clock stopping cannot rewind or hold FX ages;
shield expansion eligibility continues to read authority status deadlines.

Prepared source comparisons include original fire/charge handlers, source cast
direction, LOD boundaries/hash/frame wrap and full ordered body frames through
the presentation wrapper. `tools/test_network.ps1 -Bodies` prepares populated
ENet/WebSocket checks for body binding, same-time events, replay rejection,
live air/ground morph and shared shield phase, plus unchanged authority resources
and combat RNG. All source/scene generation, compilation and tests remain deferred.

Reference weapon/shield motion and the complete captured-body frame sequence are
written but unverified. `BodyReferenceMotion` retains emitter-specific recoil,
alternating barrels, heavy-trigger channels, launcher retraction/spread, signed
spinner remainder and authored combat key interpolation. Defense presentation
preserves local visual state versus remote shield energy gates, cast shielding,
death reset, arm/hinge/quaternion posture, expansion, projection and active-only
shader clocks. Shared morph defense phase is read/written through its original
state record; hidden trees reset canceled channels without advancing that clock.
Guard material bindings are exported explicitly rather than inferred from mesh
order. Live morph guard clearance uses the source cached joint hull envelopes.

`BodyLocomotion` composes reset, active-tree selection, displacement sampling,
gait, held-arm aim, cast/jump/species overlays, stabilization, reference motion,
morph pose, defense reapplication, weighted anatomical pair copying, shared aim,
hair/payloads, archery, equipment and final guard clearance in source order.
The driver targets the captured source-built rigs; legacy root-fold rigs remain
explicitly unsupported. Existing imported GLB walk playback is separate.

Prepared per-body oracles call original `stepLocomotion`, `stepCombatFx` and
reference/combat methods. Cases cover substep freezing, both morph trees,
charge/fire/cast expiration, defense energy/owner gates, death and landing,
invalid reference clocks, canceled hidden channels and moving hull clearance.
Original combat-key samples include every captured key boundary and interval.
Whole-frame positions are supplied at native float width before source sampling;
node comparisons retain the established native transform tolerance. No content
generation, compilation, fixture execution or runtime/transport tests have run.
Populated body binding is written above; TPS, full aim/muzzle integration,
GLB frame-order integration and rendered/transport equivalence remain pending.

World-frame, anatomical, bow and equipment pose helpers are written but
unverified. `SourceQuaternion` preserves original conjugate-only inverse,
product order, machine-epsilon slerp/antiparallel branches, non-unit composition
and X-axis reflection assignment during matrix decomposition. Column scaling is
removed without orthonormalizing shear. Native-width scalar/matrix/hierarchy
references include exact endpoints, extrapolation, zero quaternion normalization,
mirrored/nonuniform/sheared matrices and singular source results. `BodyPose`
uses the same composition for quaternion writes and retains logical Euler state.

`BodyAimPose` ports mounted-part stabilization and per-slot/always-forward weapon
axes, including the launcher extension blend. `BodyAnatomicalPose` restores
captured bases/controls before reuse, retains stance/axial yaw shares, two-link
hand bracing, bird/aim gaze and burst pluck/finger poses. `BodyArcheryPose`
retains bow carry/draw/release, string stretch, both arm targets, final aimed bow
and arrow alignment. `BodyEquipmentPose` preserves grip anchors under weapon
scaling, dorsal mounts/lifts, authored carry/stow blends and source sole/muzzle/
envelope clearance, including held-arm lift and partial-aim orientation fallback.
Presentation-effect flags are now retained for source-equivalent floor filtering.

Prepared original per-body traces compare reset and final poses separately so
later input writes cannot hide accumulated overlays. Cases include zero/partial
blend, slot gates, root mirrors/nonuniform scale, elevated feet, shared active-rig
equipment state, hair burst thresholds and bow release boundaries. Scalar math
fixtures isolate native-width inputs; whole-body comparisons retain the existing
native transform tolerance rather than claiming end-to-end double precision.
Fixture generation and all compilation/execution remain deferred. Populated
game/TPS body binding and rendered/transport equivalence remain pending.

Species-specific post-passes are written but unverified. `BodySpeciesPose`
preserves aerial held-arm aiming before cast/jump, predatory hunch/hand posture,
speed-damped ground-wing folding and per-slot tentacle-wave convergence after
cast/jump. Source references extract these exact blocks from `stepLocomotion`
and compose them with the original base gait/cast/jump helpers. Native complete
node traces retain their overwrite order, including cephalopod tentacles and
ground-wing channels. Playable body integration remains pending; complete
post-pass ordering is written above. No generation, compilation
or execution has run for this stage.

Source cast-pose overlays are written but unverified. `BodyCastPose` retains
source kind/rig signature resolution, attack/defense gains, per-clip durations,
future/expired event clearing, directional anticipation/strike and omni envelopes.
All eleven source archetypes are ported: roar, stomp, dance, spin, tailwhip, beat,
flare, swing, jab, kick and lunge, including insect lift axes and cephalopod tail
exceptions. Defaults/durations are exported from original code; scalar references
retain the discontinuity at the original anticipation/strike boundary. Prepared
per-body traces compose original gait, cast and jump helpers and compare complete
poses, latches and event state. Anatomical/aim/equipment/shield post-pass order,
game integration and all generation/compilation/execution remain pending.

Source jump-pose overlays are written but unverified. `BodyJumpPose` preserves
raw-height takeoff/landing latches, exact release thresholds, smoothed vertical
speed, jump-peak classification, apex tuck, immediate landing decay and distinct
biped/quad/insect limb load. Cephalopod compatibility tails remain untouched by
the quad jump pass. Missing heights, aerial/vehicle rigs and the legacy morph
handoff retain source early-return/reset semantics. Prepared full-body traces
compose the original base gait with original `stepJumpPose` across threshold
edges, small/big jumps, repeated apex/ground frames and source height caps.
State-only references include exact morph handoff boundaries. Complete frame
order, anatomical/equipment/shield passes and game integration remain pending.
Generation, compilation and all execution remain deferred.

Body combat-event clocks and rigid weapon mechanisms are written but unverified.
`BodyCombatFx` retains immutable shot identity, same-clock distinct rounds,
left/right/body recoil budgets, light/heavy aim holds, assumed heavy charge and
release windows, fire-lead flashes, deployment pivots, light/heavy muzzle flames
and lazy blink bases. The entity clock follows an active morph-rig change while
accepted weapon events still advance both forms. `fire_unit_motion` and
`unit_motion` retain original muzzle membership, event-age recoil/cycle curves
and independent mechanism clocks. These are presentation helpers; authority
settlement is unchanged and playable body/TPS integration remains pending.

`BodyMaterials` retains double-precision logical emission beside native material
properties. Packing preserves authored emission colors even at zero initial
intensity. Jet, morph and combat drivers share material writes without changing
another body instance. Shared body friction/damping now follows the original
negative-rate/time clamps. Prepared source traces include frozen/lazy starts,
same-object duplicates, distinct same-time shots, missing slot defaults,
cross-form clocks, heavy deadline edges, absent attack clocks, rigid recoil
piecewise edges and nonfinite mechanism time. Complete node/parent/visibility,
individual instance matrices, rig fields and material emission are compared by
new native suites; generation, compilation and execution remain deferred.

Source gait tables, body motion state, animation weights and
biped/hop/aerial/quad/vehicle driving are written but unverified.
`GaitCurves` consumes exported source fore/hind/human
curves, posture reach/lock factors and continuous walk/run support fractions.
`BodyMotionState` retains original hitstop initialization, UTF-16 identity phase,
world-velocity/acceleration damping and walk-clip rate. Animation weights preserve
finite-value priority, including an explicit zero amplitude on a flying actor.
No presentation phase consumes the combat RNG.

`BodyPose` now retains unbounded logical Euler angles and all six source rotation
orders alongside signed TRS. Quaternion writes use source Euler callbacks and
gimbal thresholds; position/scale writes preserve the logical angles. Biped/hop
drivers include separate human/animal limb topology, bound phases, movement
personality, held-weapon arm/gun recoil, chest/waist counter-rotation, head/neck
stabilization, gaze and tail curl/aim/sway. Hop legs outside the hips hierarchy
follow its vertical motion; natural arms compensate ancestor pitch after aiming.
Aerial driving retains fixed-wing pitch rules, hover/flare/bank personality,
separate bird/insect/membrane wing topology, idle/run jet length and material
brightness, axial/rotor oscillation, stable-head waves and swimming fins/tail.
Quad driving preserves walk/tripod/crawl and transverse/rotary gallop phase
sequences, grasping forelimbs, insect lift hinges, middle-leg support, soft-leg
search/guard waves, spine/neck arc compensation and rider upper-body stability.
Cephalopods use the source's separate mantle driver; their tentacle overlay
remains a later post-pass, rather than receiving the generic quadruped gait.
Wheeled/tracked rigs retain signed wheel/tread travel, differential turning,
axle steering/suspension, hull pitch/roll and recoil. Source instanced geometry
is packed as scene-local native MultiMesh resources, including per-instance
matrices/colors and complete bounds. Recognized unattached tread scratch poses
are retained separately with identity; other external node references reject.

Prepared references call original gait/state/weight/joint methods and original
`stepBiped`/`stepHop`/`stepAerial`/`stepQuad`/`stepVehicle` against original
pilot/NPC faction/Super body trees. Cases retain
complete node history, logical Euler values, lazy limb profiles, launch/brake,
idle/run/hitch frames, distinct light/heavy poses, tail turning, zero stiffness,
nullish defaults and native-precision quaternion callbacks. These fixtures and
native suites remain ungenerated/unexecuted. Original vehicle travel guards cover
negative/nonfinite time and nonfinite speed/forward/turn inputs without changing
the wheel/tread state. Native comparisons retain individual tread matrices and
private instance resources. Legacy single-tree morph driving, anatomical/combat/
equipment/shield post-pass order and playable body/TPS integration remain pending.
Vehicle rigs and full hierarchy profiles use the original faction APC/tank
builders, including Super; current hero assets do not use a wheel/track rig.
Companion geometry comparisons also retain instanced meshes and their bounds.

Original per-part morph driving is written but unverified. `BodyRig.step_morph`
uses original altitude/deadline-free damping and switches the active rig and
visible tree on the same half-way edge. `pose_morph` is a separate post-pass for
both trees: paired parts interpolate original endpoint position/quaternion/scale,
unpaired ancestors settle toward their authored rest, and single-form parts
shrink/fade on their own side of the half-way point. Original strict endpoint,
visibility, material-restore and near-quaternion thresholds are exported. The
canonical inferred part plan is required; a missing plan rejects explicitly.

`BodyPose` retains signed scales and logical quaternions independently of native
matrix decomposition, including singular poses explicitly written through that
interface. Reflection changes outside the interface reject rather than guessing
an axis. Existing body payload updates share the interface. Native morph material
changes retain original alpha/transparency/depth flags, including outline
materials. Packing now retains explicit source depth-write settings. Shader
opacity remains metadata when the original shader does not consume that property.

Prepared references run original `morphSwap`, `morphPose`, `morphSide` and exported
`morphrig.js` helpers against original per-pilot faction/Super trees. Cases include
rest-joint perturbation, partial/full settle, exact half-way edges, visible/restore
alpha thresholds, reverse altitude changes, hitch-sized steps and endpoint no-op.
Native suites reconstruct complete pose history from compact source deltas and
compare all nodes/materials; weapon traces use the same lossless delta form.
Generation, compilation and tests remain deferred. These entry points have not
yet been wired into the complete source combat/anatomical-gait/equipment/shield
post-pass sequence; actual game bodies and TPS remain pending that integration.

Full source body scene export/packing and native rig loading/weapon-event helpers
are written but unverified. The offline builder covers each pilot's ordinary
faction appearances, both mercenary factions and Super appearances. It retains
hidden nodes, outlines, combat attachments, original Euler/TRS metadata, both
morph trees and their inferred part plan. A reference table preserves shared
emitter entries, arrays/maps/sets and shared morph shield state; node/material
references resolve to native objects. Unknown node types, object types and
custom shaders fail the export rather than creating substitute geometry.

`BodyRig` loads packed native scenes and preserves original per-slot immutable
event identity: two accepted shots at the same time advance twice, while the
same event object does not. Both morph rigs receive the event; payload hiding,
next-emitter selection, alternating hands, hair clocks and attachment/flame
reparenting follow original `fireReferenceWeapon`. Payload recovery and spinner
motion use original clocks. These helpers do not yet drive full combat/locomotion
poses or replace the current unit model and FPV authority muzzle paths.

The native shield shader ports original hex cells, planar/cylindrical mapping,
Fresnel edge, flash/ripple, authored glyphs and world-curve vertex placement.
Shader identification compares original source shader strings; other custom
shaders reject explicitly. Imported colors, textures, uniform values and phase
range remain source-derived. Runtime phase sampling uses a private presentation
RNG. Materials are scene-local and attached through node surface overrides so
body effects can change one actor without changing another actor or shared mesh.
Godot [scene-local resources](https://docs.godotengine.org/en/stable/classes/class_resource.html)
provide the native instance boundary. The source MRT outline sentinel, complete
scene-wide curvature/toon/dissolve pipeline, glyph orientation, alpha/HDR/post
appearance and rendered shield parity still require implementation/verification.

Prepared native suites compare all original endpoint mesh bounds/transforms,
metadata, rendered-material references, shared emitter clocks, same-time/duplicate
shots, transported attachment parents, next world-space muzzles, payload recovery,
spinners and shield flash/clock traces. Body JSON, packed scenes and new fixtures
remain ungenerated; no compilation or tests have run. Full anatomical gait,
morph/defense/combat pose order, original aim-forward and equipment corrections,
negative-TRS driving, skill/reload body presentation, authority aim/body separation
and populated render/transport certification remain pending. Owner TPS and
authority muzzle binding are written above and depend on generated body content.

Player TPS camera/state/occlusion foundations are written but unverified and now
drive the selectable native view. `PlayerViewState` preserves original
movement/firing/defense body-heading rules, the negative half-turn camera endpoint,
synchronous mode notifications, temporary persisted FPV while aiming and the
original TPS restore order. Choosing TPS while already scoped retains the source
reentrant FPV notification and its body-to-view yaw reset. Owner input and the
authority pose lifecycle now share these rules as described above.

Source camera profiles now export `selfH` independently of damage-cylinder height.
The native TPS helper uses that ruler with original Super scaling, minimum boom
distance, shoulder offset, floor clamp and pitched local-axis recoil/roll. Shared
camera clipping uses the TPS middle-body pull anchor. Team-ring framing follows
the clip and FOV projection; the source performs no second floor/clip pass after
that adjustment. Singular projection denominators retain the clipped pose.

The existing FPV camera now includes original dynamic hazard/AA/relay colliders;
the same exported dimensions drive native movement cylinders. AA/relay radii stay
fixed when their visual model scale changes. Blocking hazards retain source scale,
zero scale uses the source default, and collapse retains reduced radius/height.
Nonblocking fields disable their movement shape. The camera cache includes the
current obstacle roster, so same-frame movement/collapse cannot reuse a stale
origin. These changes still require the final source/runtime/traversal checks.

`ViewOcclusion` provides the source nine body samples, candidate-origin filter,
scan/hold deadlines, capped linear fast-in/slow-out fade and per-instance material
restoration, including descendant outline refresh and mixed opaque/transparent
surfaces. Source `expandByObject` also includes hidden geometry and descendants
of eligible meshes; native bounds retain that detail. Native
[TriangleMesh BVHs](https://docs.godotengine.org/en/stable/classes/class_trianglemesh.html)
query mesh-local geometry without creating gameplay collision bodies. Their
two-sided segment queries replace the union of original forward/reverse casts.
Engine BVH vertex precision, grazing edges, full shader materials and populated
render equivalence still need certification. Generic scene export/packing retains
the original ring/outline/occlusion flags and material transparency metadata.

Prepared original oracles execute `_stepThirdPersonBody`, `_onViewModeChange`,
`_setAiming`, `ctrlmode.js`, camera/clip/ring blocks and the complete original
occlusion registration/fade/update methods. Native suites cover first/cleared
fade clocks, inclusive hold deadlines, backward time, hitch caps, inside-shell
views, mirrored transforms, shared/mixed materials, hidden/empty bodies,
unregistration, death clear, camera cache invalidation and unchanged combat/RNG
accounts. No oracle, generation, compilation or tests have run. Body pose,
camera-ray muzzle convergence, authority heading separation and settings/UI are
wired above. NPC mounts, animated visual-mesh queries, complete rendering,
source frame order and combined transport certification remain required for
complete third-person gameplay and model parity.

View-lock/scope paths are written but unverified. The prepared oracle executes
original `_coneAcquire`, `_tickViewLock`, `_cmd`, `_applyLook`, `_entAimPoint`,
`_isFoeEnt`, `_updateEnvFog`, `_updateWeatherFog`, exported radius/fog helpers,
the original FOV block and unmodified FPV recoil rotation block. Cases include
viewport and circular scope edges, wide/portrait/zero-sized canvases, body-centre
range, near/behind-camera rejection, one-metre obstacle tolerance, expanded
current/previous target hysteresis, stable equal-x ordering, left-to-right cycling,
closest fallback, hidden targets, release, pause, frozen system look and death/
respawn hold semantics. Death clears the previous anchor; ordinary release keeps
it. System tracking bypasses personal inversion while retaining the freeze gate.

Native view selection uses the existing measured/scaled centres, presented entity
visibility and registered-obstacle ray queries. NPCs/towers remain eligible;
Super viewers treat third-side camps as neutral. Press cycles immediately and
later scans retain the original 0.12-second deadline. Camera convergence shares
`CombatMath.view_lock_step` with bots. It changes the owner's base view through
the common look gate; it does not call weapon-lock confirmation, spend ammunition
or settle damage. The previous rendered camera/projection remains the acquisition
frame. Owner rendering composes the new base with the existing recoil/shake,
retains authority look additions, clips via the shared source camera law and
applies original FOV easing. Ordinary input carries the resulting angles on the
next update. Complete source frame-order, status prediction, TPS/muzzle and
populated traversal/presentation certification remain separate requirements.

Fire dwell, planar membership, ground/air exemptions, double-speed recovery and
death clear feed the original fire/weather radius helper. The raw radius drives
acquisition; the mask retains original one-decimal CSS anchor serialization.
Native ring and fire/weather gradients sit beneath the HUD and use exported
source palettes/stops, blur strength and opacity durations. Godot screen-texture
mipmaps and native Tween ease-out replace browser backdrop filtering/CSS timing;
these raster/transition adaptations are not certified as browser pixel matches.
The same raw densities drive both scope shrink and view acquisition. Native
[screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)
provide the renderer-owned screen copy/mipmaps, without a runtime browser bridge.

Prepared native suites compare the scalar traces, projection rosters, camera
basis/recoil retention, cycle notices and unchanged resource/RNG/weapon-lock
accounts. `-View` ENet/WebSocket paths use original scalar candidates to isolate
native ZR input/cycling, overlay release, scope uniform binding and ordinary
pose/aim transport. That fixture deliberately does not certify populated map LOS
or live roster geometry; those still require world/render integration checks.
No source oracle, generation, Godot compilation, runtime/render or transport
execution has run for this implementation. The full validation deferral remains
in force until all migration implementation is complete.

Touch/gyro/control preferences are written but unverified. Prepared references
execute the original `ctrlmode.js`, `lookPrefs.js`, `movePrefs.js`, touch
constructor/handlers/stick integration and gyro orientation/motion/watchdog
methods. Native fixtures retain exact tap boundaries, cancellation, drag versus
hold firing, independent pointer ownership, A/gesture handoff, additive keyboard
priority, continuous look-stick curves, device/scheme rules, preference clamps
and legacy screen handedness. Gyro traces include screen-axis projection,
source degree-to-radian conversion, pose wrap/jump resets, dead zones, gain,
vertical inversion and missing/yaw-dead source fallback. Pose fixtures derive
native gravity/magnetic samples from the original orientation quaternion;
expected look output still comes from the original sensor method. The original
flying-input block supplies level-move direction fixtures. No oracle, native
suite, compilation or device/render/transport check has run for this stage.

A native ConfigFile stores personal controls; only Session authority broadcasts
set the room override. The host can change it during a match. Forced kbm/pad
reject personal scheme changes; any retains the player's own saved choice.
These settings do not authorize client gameplay settlement. Level-move is a
strict input boolean used by authority flight physics. Touch, mouse, keypad and
gyro share one look/inversion gate. Mode/overlay/focus transitions release owned
pointers and suppress held physical controls until release, including emulated
mouse fire. Dead fire input cannot remain queued for respawn. Touch controls
stay available during death for the shop, which now has a native return button.
HUD mirroring and button mirroring are separate. Native touch/HUD placement
uses Godot's mobile display-safe rectangle, transformed into canvas coordinates. The current single-drone source
has no alternate squad member; its swap button explains that restriction.
ZR view-lock is enabled after original view metadata is imported; missing
metadata keeps the control explicitly unavailable.

The native backend polls Godot gravity, magnetometer and angular velocity;
[Godot Input](https://docs.godotengine.org/en/stable/classes/class_input.html)
provides sensor values on Android/iOS and zero elsewhere. There is no runtime
browser bridge. Valid gravity plus nonparallel magnetic data defines the
orientation path; missing vectors never fabricate an identity pose. Godot's
[Android sensor handler](https://github.com/godotengine/godot/blob/4.5-stable/platform/android/java/lib/src/org/godotengine/godot/input/GodotInputHandler.java)
already rotates values to screen axes; native polling does not rotate them a
second time. Motion data is already radians per second. Initial all-zero motion
cannot prove a sensor exists, so it remains waiting until a nonzero sample;
source watchdog failure stays visible and disables the preference. Native
hardware capability, platform coordinate conventions, input sampling, device
rotation, safe areas and complete mobile exports still require certification.
Native automatic control selection uses touchscreen availability, mobile OS
pointer assumptions and screen dimensions; pure decision fixtures do not prove
physical hybrid-device/DPI detection parity.

Prepared `-Mobile` ENet/WebSocket paths inject native screen-touch/drag events,
check shared inversion and authority level-move input, receive live host mode
changes, reject non-host changes, restore personal choices in any mode and
verify aim acknowledgements plus overlay release through actual authority input.
Fixture generation and all execution remain deferred until all migration
implementation is complete.

Controls/recoil paths are written but unverified. Unexecuted references execute
original `_applyLook`, `_moveAxis`, `_moveInput`, `_tickNumpadLook`, `_rmbDown`,
`_rmbUp`, `_fireHoldAbility`, `_recoiling` and `_recoilMoveF` methods, plus
unmodified `_tryFire` gate/burst/recoil blocks, `_burstEchoSelf` recoil and
`_updatePlayer` decay/shake blocks. Native input follows the current executed
RMB method: immediate stance-selected cast. Older source comments describing
hold/tap gestures do not override that producer. Wheel and keypad +/- toggle
scope/weapon mode with original throttle; arrows move, keypad chords retain
additive diagonal/overlapping-key look, and keypad */ fire/cast. Native look
uses original sensitivity/pitch bounds and frozen-body gate. Overlay entry
suppresses held controls until released. Frozen human casts/shield toggles and
blind entry into aiming reject through authority rules. Ranged strike/EMP casts
retain the confirmed-lock gate; the current authored roster has no such ranged
producer. These dormant seams do not admit unsupported effects.

Reliable aim actions carry monotonic acknowledgements. Ordinary movement packets
retain the authority's mode, so stale movement cannot undo a toggle or turn
heavy aiming back on after its magazine empties. Current mode and recoil state
are private to the viewer. Source action cooldowns/resource gates replace the
old global 80 ms action-drop rule, which otherwise discarded adjacent shield and
RMB actions. Local replica look updates the native camera immediately and clips
against the existing world; authoritative settlement still consumes accepted
input. No client HP, damage, ammunition, purchase or outcome settlement is added.

Native primary fire preserves its pre-kick direction. Accepted recoil is applied
after launch/settlement, so that same shot does not aim through its own kick.
Subsequent controlled movement reads the previous recoil state; echoes add kick
before movement, followed by original exponential decay and trauma-squared
view shake. Strict movement penalties survive swapping to weaker weapons until
recoil decays below the source threshold. Airborne kick and input-penalty factors
stay distinct. Reverse impulses remain outside the walking multiplier. Echoes
use the shared source queue law but add no second resource/damage budget. Bots
retain source AI movement/fire behavior rather than receiving player camera
recoil. Death clears active recoil and both physical/visual echo queues. The
native gate retains original burst settling and steady/rail release semantics;
current authored steady and rail charge values remain zero. Independent recoil
randomness never consumes combat RNG. Prepared native cases compare all pilot
profiles in ground/air states, stronger-to-weaker shots, echoes, recovery,
release and source RNG draw counts. ENet/WebSocket `-Controls` paths drive real
wheel/F/RMB events, ordered stance cast, reliable mode acknowledgement and native
primary-fire/private recoil against the original pulse trace. Fixture generation,
compilation and all runtime/render/transport execution remain deferred. Full
body/view presentation, spectator controls and complete source
frame-order/traversal/camera certification remain pending. Touch/gyro and personal
control preferences now have the additional unverified implementation above.

Unexecuted Super references call original `_setSuperLvl`, `_buySuperUpg`,
`_deathPenalty`, `_chargeLvl`, `_superSpawnPoint`, `_spawnAutonomousSummon`,
`heroWeapon`, `heroAbility`, `selfAtkBoost`, `_gateFire`, `selfH` and `_eyeH` seams. Native
combat consumers read the same effective fractional tier, including magazines,
reloads, ability casts, heavy/lock budgets and private cockpit events. Source
weapons/abilities are exported at all 101 legal Super levels; defense curves and
capped charge factors are generated directly from source helpers. Purchases and
death penalties share one authority recomputation path. Alive bodies gain only
new capacity on upgrades, downgrade clamps current HP/shields, dead bodies keep
their depleted state, and both magazines/reload deadlines are cleared lazily.
Only changed levels emit a purchase event. Super summons capture both effective
ability growth and the source creep multiplier when spawned; existing summons
retain their strength. Clone bodies retain their source unscaled geometry while
reading the owner's current weapon for autonomous fire. Fractional magazines
keep their final positive fraction spendable before reload. Dedicated carrier
loop counts retain source ceil semantics while bomber drop arrays retain floor
semantics; fractions, scatter angles and lifetimes still use the raw interpolated
count. Source carrier launch fixtures include fractional Super tiers across every
pilot, with original allocation, launch positions and RNG draw counts. Additional
original cast cases cover Super clone/beacon production and current weapon tiers.

Native Super body, hit cylinders and aim-centre scale increase at each 20-level
boundary up to six times. FPV eye and forward offsets follow source `selfH`;
charged crouch remains an absolute displacement. Respawns retain yaw, sample
240 source candidates with native Z conversion, reject lanes/live structures,
terrain hazards and blockers, prefer separation from that peer's last point,
then use the original farthest/centre fallbacks. Sampling uses a separate native
random generator and never consumes combat draws. Both faction bases may repair
the Super body; outcomes still name the faction whose enemy base fell. The
third-faction HUD preserves weighted last hits. Native mode selection permits
all pilots, retains one human and fills both regular Bot teams. Ordinary tracks
and faction creep purchases are excluded. The Super shop starts automatic
purchase enabled, sends one request per observed level with source retry timing,
and relies on authority settlement. Missing Super metadata leaves deployment
unavailable. Prepared native suites cover all pilots, fractional/boundary levels,
idempotence, alive/dead downgrade, charge caps, summon strength and seeded spawn
selection/draw counts. ENet/WebSocket `-Super` cases cover roster/stats, a 19→20
purchase, 20→19 death shrink and relocated full-health respawn. Generation,
compilation and every runtime/render/transport check remain deferred; these are
implementation paths and prepared cases, not passing parity results.

Unexecuted campaign references call original progress/intro persistence functions,
`startStoryChapter`, `launchStoryBattle`, `rollSideSwap`, `venueConfig`, `addHero`,
dialogue line timing/portrait selection and cinematic camera/focus methods.
Native campaign deployment preserves chapter-specific pilots, allied/enemy Bot
assignment order, fixed environment and increasing difficulty. Campaign rooms
roll base assignment before launch and use the corresponding exported map;
resource availability requires both assignments and the original structure
profile. Native ConfigFile persistence keeps factions separate, marks intros
on entry and grants chapter clearance only after the authority match outcome
reports that faction's victory. Dedicated hosts do not grant local story progress.
The first visit displays the source prologue; chapter intros can be replayed.
Native controls retain automatic crawl with manual pause, nearest-section focus,
responsive bounded pan/zoom, image fallback, double tap/long press skip and
source fade durations. PNG portraits/art and narrative text come from original
content. Source radio lines use UTF-16 length for timing, stable frequency ties
for portrait leads, and timer generations that cancel obsolete scenes without
blocking combat input. Front/middle BOSS events start radio; only victory shows
the base-stage transcript. Exit clears scene timers and returns to the faction's
updated chapter menu. Missing scenes are omitted, never substituted.

The offline map exporter includes each chapter's original asymmetric single-lane
config for both viewing factions and both source room base assignments. The
capture tool reuses original OSM/Terrarium capture functions and writes only
workspace archives; world baking consumes those verified responses. Campaign
resources do not use an invented arena when captures are absent. Prepared cases
check original deployment requests, faction saves, Unicode timing, cinematic
focus/pose, portrait order, radio cancellation and native starts across all
campaign map assignments. ENet/WebSocket `-Campaign` cases cover named rosters,
stage snapshots, HP-one floors, permanent BOSS death and non-blocking radio.
These fixtures/captures/resources, compilation and all runtime/render/transport
checks remain deferred and unexecuted. This is not campaign parity certification.

Unexecuted bot references call the original `BotBrain.update`, `_op`, `botFire`,
`heroBurst`, `heroPlasma`, `_hurtLog` and `_shotOrigin` methods. The decision
sequences isolate native movement and settlement callbacks; separate cases
exercise the original resource and damage paths across authored weapon tiers.
Native AI preserves constructor RNG draws, reaction/error attempts, lazy heavy
refill, difficulty operation budgets, resolved role policies, retreat/rally
hysteresis, hold zones, threat fade and elite blood-screen alert inversion.
Desired movement goes through the same native body sweep as human collision;
the source completion ratio drives alternating wall skirts. Fresh source bots
do not write human movement speed for evasion, so the native AI retains that
zero value (or the last human value at takeover) rather than inventing dodge
chance from bot motion. Pilot trails keep one sample before the retention window;
bot impact reports use the original history scan and reload backdating. Direct
bot attacks retain immediate authority settlement and every-third light-shot
broadcast; blast/fan/secondary line hits retain their source status/crit ordering.
Native wall/replica checks and ENet/WebSocket `-Bots` cases are prepared. These
cases have not been generated or executed and do not certify full matches.

Unexecuted siege/BOSS references call original stage/segment helpers,
`_bossAnchor`, `addHero`, `_bossSync`, `_bossEnrage`, `_applyUpg`, `_damage`,
`_kill`, `_reviveBody` and `_updateBossBar`. Native stage counts include both
structures and BOSS bodies. Later stages reject damage and target acquisition;
the current stage's buildings remain targetable and lose HP down to one while
a local BOSS survives or its dialogue timer remains active. Only the final BOSS
at each stage starts the timer, and the base stage unlocks immediately. Boss
deaths keep an infinite respawn deadline, reject revival and avoid human death
penalties. Segment progression follows original weighted HP thresholds, advances
all eight tracks through the shared upgrade seam, preserves HP fraction while
expanding capacity, and then restores shields and grants transition immunity.
Native model, aim-centre and collision volumes use absolute source stage scale.
The final stage retains source damage/cadence/reload/cooldown/mobility and NPC
resistance factors. Allied bot damage reduction and source base-support armor
are settled centrally. Prepared HUD cases retain nearest visible BOSS selection,
stable ties, obstacle endpoint tolerance and three-second look-away hysteresis;
the native segmented bar uses source fill/frame colors. ENet/WebSocket `-Bosses`
cases compare authority and replica upgrade/shield/volume transitions against
the original trace. These metadata/fixture/transport/render paths remain
ungenerated and unexecuted. Campaign event/progress paths and original arena
generation are now written below the verification boundary. Resource generation,
Full BOSS/Super VFX and complete chapter/mode certification remain pending.

Current source routing audit finds 64 authored slots across 32 characters, all
with native effect paths written; carrier/companion paths still require their
ungenerated source resources. Legacy storm/boomerang/tree/moon/harpoon/link/mine/
infection/support helper branches have no current `heroCast` producer in the
authored roster. Keep those branches unavailable unless another active source
producer is found. This routing audit is not feature-parity certification:
climate, body/visibility/projectile interactions, aiming/UI and full integration
still require implementation and final verification.

Unexecuted status references call the original `_castEffect`, `_interruptCast`,
`_readyCharges`, `_dodgeP`, `_damage`, `_applyHitEmp`, `_applyHitElem`,
`_tickElemBuildup` and `_tickPhaseShift` methods, plus original shield-bash and
NPC-fire tick blocks. They cover all authored tiers admitted by the native
effect gate, fractional/once-only effects, charge deadlines, motion/altitude
gates, elemental stacking/decay, defense sectors, reflection, freeze, vamp and
interrupted healing before shield overflow. Ungenerated carrier content and remaining
special-entity producers stay outside the gate. Native suites also preserve source RNG draw
counts and distinguish explicit entity effect radii from computed hit volumes.
These prepared cases do not establish passing results or full ability parity.

Unexecuted companion references call original `_spawnClones`, `_despawnClones`,
`_autoTarget`, `_tickClones`, `_spawnAutonomousSummon`, `_tickSummons`,
`_tickDecoyBeacons`, `_castEffect` and `_damage`. Cases retain current-stat clone
HP/shields/armor, current owner weapon tiers, independent crit/cadence, additive
target priorities, extended owner focus, stable ties, zero-fraction summons,
per-spawn combat RNG draws, owner death, expiry transfer and lethal donor removal.
Source expiry swaps use solid placement; lethal swaps bypass horizontal collision.
The original recast helper clears newly assigned clone/reload timers even when
the previous roster is empty; this source behavior is intentionally preserved.
Clone bodies retain hero damage rules while remaining outside player input,
camera, pilot binding, regeneration and respawn loops. Hits to clones interrupt
their owner's cast, and clone damage uses relative height frames and the owner's
fluid state. The newer non-hero summon kinds retain the source distinction
between their actual flight altitude and their ground-based damage/LOS target
bands; prepared frame fixtures compare original `_bodySpan`, `_sightY`, `_eyeY`
and `_tgtY`. Summon/decoy hits stamp owner assists and focus; clone hits keep
independent focus. Summon kills pay the owner's assist share. Clone kills do not
transfer full bounty or kill score to the owner; source undefined clone money
is represented by a non-spendable native zero balance rather than a NaN snapshot.

Holograms retain captured light range/rate, current owner light damage at 0.3,
direct horizontal movement and confusion on corpse/expiry detonation. Autonomous
summons have no invented lifetime and can keep fighting after their owner dies.
The offline exporter now captures both factions of six dedicated source summon
graphs plus the original hologram wingman alias; `--companions` packs them into
native scenes without resizing their visual graph to the separate hit volume.
Missing companion resources reject before ability spending. These graphs and
fixtures have not been generated or packed. A prepared native wire-encoding case
checks that clone snapshots sharing an owner's peer ID cannot replace or remove
the owner's pilot binding. Climate factors, full NPC attraction,
source visual animation, carriers and populated transport/render cases remain
pending; the prepared companion suite has not run.

Unexecuted carrier references call original `_launchOrigin`, `_launchAtkCarrier`,
`_tickDecoys`, `_tickKamis`, `_tickHypers`, `_atkArrive`, `_castEffect` and `_damage`.
Native point delivery keeps separate bomber/kamikaze/hypersonic actor rosters,
source-derived HP, zero armor/shields and shootable native areas. It shares the
existing effect settlement instead of adding a generic warhead. Authority aim
derives the source decimetre point and planar range clamp; attack launch uses
the nearest living allied tower/base with stable ties and the source hull fallback.
The minimum leg is measured from this origin while fuel retains the original
unextended distance. Scalar flight remains independent of world movement
collision and the pilot altitude ceiling; actual scene positions are synchronized
from those scalars before delivery/removal.

Dedicated s01 formations, m06 timed drops, t01 single warheads, t09 concentric
scatter and m07 delayed progressive scatter retain original RNG draws and
fractional/integer budgets. In particular, overridden actor counts do not change
the original chassis divisor used by `atkPartN`. Native effect settlement now
accepts an explicit integer count so a zero budget cannot invent another strike
or summon. Bomber expiry does not deliver outstanding drops; intercepted actors
pay the source NPC kill reward and cancel their effect without a generic blast.
Delivery accepts an existing dead owner but rejects an absent pilot binding.
Hypersonic ascent, apex transition, one-time terminal tracking and contracting
horizontal spiral have prepared original tick sequences, including deferred
launch, stale/dead targets and the closed antipodal turn boundary.

Offline scene export now includes both faction bomber/hypersonic bodies and
character-specific half-size kamikaze forge graphs. The prepared carrier suite
covers producers, flight laws, origins, shared arrival, strike budgets and
interception. Carrier HP metadata, graphs and fixture rows have not been
generated, packed or executed. Missing carrier content keeps casts unavailable
before spending. Full source aiming/body integration, source flight VFX/body
reaction, complete NPC targeting, disconnect cleanup and populated terrain,
render and transport integration remain pending.

Unexecuted NPC/economy references call original `_tgBlockedD`, `_acquireTarget`,
`_acquireCached`, `_buildTickIndex`, `_damage`, `buy` and `_buyCreepUpg`. The offline
import reads actual targeting cell/rescan constants from source code rather than
stale explanatory comments. Native NPC selection uses source planar eligibility,
weapon-height/fog envelopes, upward-fire compensation, hologram/hero/weapon
weights and lazy LOS checks. Its temporary sorted cells preserve original
cell-x/cell-z/insertion ordering; direct calls outside the NPC phase retain the
original full scan. Native physics validates held targets every frame while
preference rescans use the original server tick period. Pilot movement is now
settled before the NPC targeting phase. Combined source frame-order and actual
obstruction integration remain unverified.

Creep upgrade levels belong to faction lanes, unlock after all eight tracks are
maxed, charge one fixed payment and affect newly spawned waves. Existing bodies
retain their captured multiplier. Hero attacks ignore the creep durability
upgrade; non-hero attacks use the original per-penetration EHP conversion.
Creep outgoing damage scales only against non-hero victims, including each blast
recipient; source bounty stays unchanged. Shared lane levels and actor multipliers
are included in native snapshots. The shop uses a native scroll container and
per-lane upgrade buttons. Its native action payload requires a decimal integer
lane and rejects malformed encodings instead of coercing them to lane zero.

Source upgrade purchasing is available remotely and while waiting to respawn.
The previous invented base-distance/alive gates were removed; purchasing HP or
shield capacity during death changes caps without resurrecting the body. Source
purchase oracles are prepared for all eight tracks and faction lane rules. These
fixture rows have not been generated or executed. Wave prefill/spacing/cohesion,
complete source movement, balance preferences, boss/super upgrade routes and
populated UI/transport validation remain pending.

Unexecuted wave references call original `_spawnLaneWave`, `_prefillLanes`,
`_waveAnchors`, `_advance`, `cumLen` and `pointAt`. Placement/movement coefficients
are extracted from those source methods; composition and steady wave spacing use
the original data helpers. Every offline map/team variant now has a source
prefill-recipe export path, including original lane/side order and negative
prefill wave IDs. Actor spawning preserves two combat RNG draws per member,
mirrored north/south jitter, the source six-metre tail spacing and the base
spawn-progress floor. Terrain grade does not inflate planar progress or prefill
spacing. Regular waves advance their index before spawning and retain the
original first-wave deadline.

Native NPC logic now steps at the original server period while pilot physics
remains native. This preserves source constant per-step lane convergence and
countdown fire cadence. Wave anchors exclude dead, hero, laneless and previously
engaged members. Stun halts progress, slow scales it and confusion reverses it;
held members still converge and resolve sequential structure/hazard/ally pushes.
The current native integration uses the original structure/ally rules plus
Godot body sweeps and native deck/tunnel standing layers. Captured structures
retain source tick lifetime; removed/dead allies stop pushing. Source hazard
rosters, complete wind/surface integration, physical traversal/support, crowd collisions,
populated rendering and transport still need complete integration. Prepared
scalar/reference suites do not certify these combined physical cases.

Wave metadata, all 90 prefill recipes and the prepared source fixture rows have
not been regenerated or executed. The constructor explicitly reports missing
source prefill/rule data instead of silently inventing a wave layout.

Unexecuted weather references call original `weatherVectorAt`,
`computeSolarSchedule`, `resolveWeatherDynamics`, `stepWeatherSurface`,
weather movement/lift/accuracy helpers, `resolveWeatherVisuals`, `_tickWeather`,
`_lightningShockwave`, `_reloadT` and `_damage`. Native climate advances on the
original server period and uses independent deterministic snow/lightning draws.
Surface history retains the source exponential capacities/drying and delayed
cover thresholds; freeze retains its 18-second hold and partial-step melting.
Airborne precipitation does not slow flight in the current source. Raw weather
intensities still govern lift/cooldown/damage even when cloud gates suppress
visible precipitation. Ground cadence uses deposited sand, while airborne
cadence uses the original intensity precedence. Rain applies only to attacks
with source weapon definitions and is not applied again to reflected damage.

The source authority has no client-global solar schedule: its weather-vector
bias uses fixed phase anchors and its night accuracy uses the offline solar
orbit. The native renderer uses the latitude/season solar schedule, preserving
that source distinction. Native `WorldEnvironment` depth fog, procedural sky,
directional light and GPU particles consume exported source palettes and
precipitation profiles. Complete source clouds, fog banks, veil/fine layers,
contacts, deposit/scorch appearance and celestial body visuals remain pending.
Weather vector/dynamics/surface history are authority snapshot state for all
transports. Visible lightning points are filtered with the recipient roster.

Prepared snow/lightning cases cover threshold gates, once-per-second draws,
per-actor cooldowns, selection without replacement, planar shockwaves, scorch
clearing and unchanged combat RNG. Prepared damage/reload cases exercise the
original authority seams. Scenery strikes/fire now have source grid/obstacle
capture and native rule paths; the complete geography/hazard roster remains
pending. Weather metadata/fixtures have
not been regenerated; no compilation, tests or rendering have been performed
for this implementation. Combined entity lifecycle, controller/physics,
traversal, visibility and network certification remain required.

Unexecuted environmental references execute original `terrainEnvCode`,
`envTrigger`, `_envAt`, `_terrainSlowF`, `_terrainJumpVelocityF`, triangular
terrain sampling, dry-band distance, `_ingestWorldWet`/`_wetAt`, tide/fire
helpers, ice surface/ceiling branches and `_fireBurn`. Source world baking now
captures the actual height field and dry-band capsules, original 20m mirrored
wet grid, marine/base-water profile and source water/swamp meshes. Native world
resources require these captures explicitly; the earlier saved resources have
not been regenerated. Current offline baking uses the original missing-imagery
path and rejects an uncaptured image-color or border-band classifier. Full
imagery/geography and rendered border-band producers remain pending.

Player immersion is derived from authority position, full body height and
standing surface. It preserves shallow-water speed caps, gradual marsh depth,
jump/air exemptions, full immersion reduction and partial submerged freezing.
Native ice constraints supplement Godot solid collision: submerged feet cannot
descend through the frozen floor, nearby feet mount the plane and deep feet
retain an ice ceiling. Water height follows the original marine-only lunar
tide; coarse neutral-avoidance grids remain the original starting-time capture.
Current source water/swamp geometry follows tide displacement, while its wave,
shore, underwater and ice appearance still require native presentation.

Frozen fluid DOT uses the source proportional HP/shield burn and stamps combat
time without armor, rain, fluid or phase damage reductions; invulnerability and
garrison gates remain distinct. Weapon damage and raw burn share one authority
death helper, including clone transfers, attribution, assists and outcomes.
Prepared burn fixtures include simultaneous shield/HP loss, exhausted shields,
zero/negative amounts, protection gates and prior bleed killer attribution.
Scenery lightning/fire now use source height/obstacle capture; the complete
geography, hazard seeding and collapse lifecycle remain pending. No environmental fixtures, world resources,
compilation, tests or render/transport checks have been executed for this work.

Unexecuted scenery references call original `_ingestHgt`, `_hgtAt`,
`_strikeWeatherSurface`, `_tickHazards`, `_rebuildAvoidZones` and
`stepFireVisual`. Authority height preserves original cell-center ASCII
quantization, Float32 decoding and bilinear sampling, independently of the
player's precise triangular terrain field. Original wet/height grids and
normalized collision-column profiles are captured in offline road-world
resources. Original authority bounds are exported separately from terrain
coverage. The current road-only capture follows the source no-camp ingest
branch. Runtime camp clearance now follows the original legacy-centre and
grouped-building rules; complete scenery/building visual clearance and
geographic rosters remain pending.

Scenery lightning uses two independent location draws, mirrored coordinates,
source circle/oriented-box top selection, wet/slab exclusion, four-point ring
boundaries, grade threshold, precipitation gate and global live-fire cap.
Scorch footprints deduplicate in three dimensions. Its shockwave uses existing
authority settlement, while the fire's visible ground anchor uses the precise
terrain field. Fire expiry, effective-precipitation extinguishing, raw-weather
quench/wind boost, source ground-jump and smoke-height eligibility, event
throttling, proportional burn and neutral avoidance are written. Fire/scar
records share the existing authority snapshot path; scenery strike points carry
their original absolute-world marker. Complete event/visibility certification
remains pending.

Offline hazard export includes every source hazard, AA site, relay, the original
missing-imagery mine bump and the actual-radius lightning fire scene. `--hazards` packs them through the native scene importer,
which now retains source vertex-color AO. Native fire/smoke poses follow the
original flicker, scale, wind lean/drift and opacity functions; mesh/material
resources are private per visual instance. Prepared pose fixtures execute the
original visual function. These initial graphs use canonical seed zero;
per-entity source geometry variation and variable-radius collapse shapes remain
required. Permanent scorch/deposit appearance is not yet rendered. Hazard
graphs, grid captures, fixtures, compilation and full render/runtime/transport
verification have not been generated or executed.

Unexecuted scene references call original `_seedMines`, `_seedHazards`,
`_seedVehicles`, `_ensureConnectivity`, `_seedAASites`, `_seedRelays`,
`_pruneCorridors`, `_collapseScene`, `_tickMines`, `_tickAmbush`, `_tickRelays`,
`_spawnLoot`, `_tickHazards`, `_applyCollapse`, `_updateLoot` and `_updateMines`.
Native scenery generation consumes a separate seeded stream in the original
order. It retains biome weighting, conditional turn/midpoint draws, short-wall
overlap exemptions, radius-aware lane clearance, wet exclusions, parked-car/ship
placement and the twelve-removal connectivity limit. Four-way `AStarGrid2D`
replaces only the source reachability traversal; sample/blocker/removal order
remains source-derived. Corridor profiles come from the original upload ingest,
including its width clamps and count limit. They clear scene bodies from bridge
and tunnel corridors, while only tunnel corridors clear mines.

Physical scenery has original hash/HP/armor, invulnerability and EV metadata.
Destruction retains blocking rubble, changes only the first co-located blocker,
uses source collapse pose/parity and bounded fire duration, then rolls original
salvage through the combat RNG. Neutral kills do not award battle score. Cash,
ammo and timed-affix loot retains rare-tier overflow, mirrored scatter, expiry
before pickup, insertion-order winners, inclusive altitude/radius limits,
reload cancellation and same-affix deadline refresh. `--loot` packs original
cash/ammo/affix scenes; native presentation preserves root rotation and first
child bobbing. Loot and mines share authority snapshots.

Mines retain primary-pilot trigger gates, ordinary/charged jump thresholds,
reverse mine order, planar blast falloff without target-radius expansion and
the source airborne-hero exclusion. AA ambush retains the flight/corridor/
stealth gates, shared 180-second threat cooldown, stable nearest-site selection,
combat RNG draw order and one active ambush missile limit. Its launches use
the existing shootable/interceptable missile path. Relays preserve reverse
capture order, contested/empty decay, side-switch reset, whole-team vision and
one-time removal. The original corridor prune removes relay actors but leaves
their capture roster; the native authority retains this behavior explicitly.
Source single-body/mode lifecycle and the written missile-defense rules still
require complete combined integration and final verification.

Flood zones compose their first matching speed cap with terrain slowing and
override terrain jump velocity with the source water square-root factor; flight
and off-ground movement are exempt. Prepared original flood cases cover those
gates. Mine presentation uses the original no-imagery model, full 3D proximity,
opacity ramp and 0.12-second throttle. Per-location imagery color, full damage
deformation/cracks/debris, per-entity seeded hazard geometry, conforming flood/
pothole meshes, relay progress/strike visuals and complete scenery content remain
pending. No new scene/flood/loot fixture, asset, compilation, runtime, render or
transport validation has been executed.

Unexecuted supply references call original `_rollAirdropSize`, `_airdropPoint`,
`_spawnAirdropWave`, `_tickAirdrops`, `_grantReward`, `_openAirdrop`, `_frame`,
`_healBody`, `bossSegCapF` and the original power-regeneration tick block. Native
airdrop scheduling retains the first sixty-second deadline and current-time
rescheduling, player-count batches, live-box cap, forty-attempt placement,
lane/base/obstacle/terrain rejection and source combat draw order. Failed points
do not invent a replacement or consume a size draw. Boxes retain original
expiry-before-landing/pickup order, reverse box iteration, inclusive pickup
height/radius, insertion-order winners and equal-probability reward selection.
Public snapshots preserve mirrored decimetre half-tie rounding and landing
flags without exposing future rewards.

Medical supplies report actual restored HP and the original nominal shield
amount. Batteries may exceed maximum power, shorten absolute ability cooldowns
with a zero floor and move charge-recharge deadlines no earlier than current
time. Regeneration now preserves overcharge until spent, matching the original
tick block. Allied civilian follow timers now produce shared authority rewards.
Healing respects hero-only amplification and
the source boss skill-only reduction/remaining-segment ceiling; these helper
rules do not establish campaign/boss lifecycle parity.

Offline `--loot` packing now includes original S/M/L airdrop graphs and their
crate/parachute/ground-parachute/halo node bindings. Native descent preserves
the source first-seen clock, quadratic height, zero-clock branch, descent-only
root rotation and landed crate spin/bob. First seeing an already landed box
starts its ground presentation immediately. Complete populated/late-join
transport timing and rendered effects remain unverified.

Supply, loot, relay and threat feedback uses native `VBoxContainer`/`Label`
nodes. Feed limits and lifetime are captured from the source HUD (newest first,
five rows, six seconds); Traditional Chinese messages belong in `data/ui.json`.
Public airdrop/relay events survive actor visibility/removal filtering, while
neutral scene bodies remain absent from the minimap as in the source. Prepared
supply cases cover placement exhaustion, caps, deadline/radius/height edges,
reward/charge/overcharge behavior, item/boss healing, snapshots, public events,
authority rejection and original descent node poses. Source graphs, fixture
generation, Godot compilation, UI/render/runtime smoke checks and transport
verification have not been executed.

Unexecuted third-party references call original `setWorld`, `_seedCamps`,
`_campHome`, `_tpBehave`, `_tpAggroTarget`, `_tpMove`, `_tickCamps`,
`_onThirdDeath`, `_freeCampCivilians`, `_damage`, `_seedCivilians`, `_spawnCiv`,
`_civPoint`, `_civWander`, `_moveCiv`, `_tickCivilians`, `civInteract`, `_kill`,
`civilianBody`, `generateCivilian`, `civSpeed` and the original client
`_clearAroundBunker`. Camp placement preserves
source lane/side order, two sampling rounds, stable candidate ties and the
separate scene RNG. Legacy obstacle clearance tests the pillar centre against
the strict sixteen-metre radius; keyed multi-volume buildings use their shared
oriented bounds and are removed as a group. Captured obstacle metadata retains
building identity for this rule. Native physical/camera clearance preserves
unkeyed bridge/vegetation pillars, matching the client distinction. Replicas
clear keyed buildings on first bunker discovery, retaining the source rounded
position cache across hide/reveal and respawns. Weather obstacle metadata uses
server clearance; native LOS still needs to compose server-only legacy removal
with retained physical pillars during full environmental integration.

Authority camp actors keep source faction compositions, slot arcs, helicopter
altitudes and the existing NPC firing path. Soldiers seek a living bunker at
half HP, respect three garrison slots, recover three percent of maximum HP per
second and leave only at full HP or when the bunker disappears. Garrison actors
are hidden and immune, with disabled body/hit layers; initial snapshots still
create their collision shape. Retreat, pursuit, aggro expiry, terrain-edge
escape and ordered blocker pushing retain source gates. Member respawn clocks
pause while a bunker is absent, including its rebuild tick. Complete clearance
releases four civilians once, with source attacker/nearest-living-owner choice.
Super/third mutual immunity exits before aggro/assist/focus settlement;
incidental damage between third factions remains possible.

Civilian seeding preserves source side order, spy slots and placement/profession/
pause combat draws. Respawns preserve allegiance and spy identity, reroll the
profession and retry failed placement without dropping the queue entry. Flee
precedes follow and wander; expiry removes a civilian without a death reward or
respawn. Lost/dead/distant owners release followers, and only allied followers
produce profession supplies. Signed civilian/spy kill credits retain source
rounding and zero-money clamping without battle kill scores. Liberated civilians
never respawn. Replicas cannot advance these clocks, generate actors or settle
interactions/rewards. Public snapshots never expose spy or private path state;
identity is revealed only by the source kill report.

Independent body and appearance RNG preserve the source height/waist/hit-volume
rules, age/gender draw short circuits and profession titles. Offline export
prepares original camp graphs and forty canonical civilian graphs across the
two factions and twenty professions; source team rings remain faction-specific.
Those civilian graphs use seed zero and are scaled to the exact per-ID body
dimensions. Full per-ID clothing/parts/palette geometry, measured mesh centres,
source rig motion/overhead marks and building visual clearance remain pending.
The authority lifecycle and native G/H prompts/reports are written, but their
source resources, fixture generation, compilation, populated rendering,
runtime smoke and transport checks have not run. This stage is not full parity.

Unexecuted match-stat references call original `_kill` for hero, creep,
tower/base, third-party, neutral scenery, civilian and carrier targets, with
hero/NPC/third/ally/environment killers and near/far contributors. The native
authority owns regular-match faction counters. Every settled hero death raises
its faction deaths; an enemy killer raises kills only when its faction has a
counter column. GUER/MILI therefore raise a victim's deaths without inventing
third-faction scoreboard rows. Assist counters rise only after a nonzero bounty
is actually paid, preserving source range, killer exclusion and zero-bounty
score distinctions. Creep last hits retain `UNITS[kind].bounty || 1` weighting;
neutral/civilian/carrier early returns do not fabricate last hits.

Counters are copied into public snapshots and detached again on replicas;
stale packets and incoming authority packets cannot overwrite them. Native HUD
rows use source faction colors and Traditional Chinese data labels. Prepared
cases cover initial columns, death settlement, snapshot copy isolation and
replica authority rejection. Single-body/frame-order, super/story/mode
producers, leaderboards and replay integration remain pending. Fixture
generation, compilation, HUD/render/runtime smoke and transport validation
have not been executed.

Unexecuted persistent-field references evaluate original `_castEffect`,
`_tickCubicSlabs`, `_tickFogs`, `_visionSources`, `_visibleTo`,
`_skillBarriersBlocked` and `spawnFogVFX`. Cube fields retain six panels, rounded
fractional HP, unscaled lifetime, partial destruction, corpse/expiry removal,
raw continuous damage and the source distinction between explicit effect radii,
computed damage bands, visible boxes and logical LOS planes. They do not add
movement walls or a bounty for destroyed skill objects. Casting rejects an
unverified panel standing surface before spending resources.

Fog retains unscaled duration/corrosion at zero interruption fraction, explicit
recipient radius, deterministic poison buildup, a single 0.333 sight multiplier,
and insertion-order selection of the first protecting allied field. Private
actor rosters use these same visibility gates; public fog records contain only
their presentation geometry/time/side. Native fog uses the original disk/five
rings, faction-relative palettes, rotations and final-fifth disk fade, including
the source absolute 0.5-metre anchor. Slab renderers retain the original bronze
and rune box dimensions and rotations. Shader appearance, full visual-mesh
integration, field transport and populated-scene rendering remain unverified;
no persistent-field fixture has been generated or executed yet.

Unexecuted movement references call original `_stepLift`, `_chargeJump` and
`_morphLaunch` with source Three.js vectors and the original cost/sink helpers.
They isolate flight power, altitude cost, descent recharge, unbalance locks,
charged launch velocity and resource spending. Native collision/traversal,
combined weather/water, source bot movement and full frame-order equivalence
still require final integration cases. The removed explicit morph command is
replaced by charged launch/automatic landing; the existing camera transport
fixture now selects forms directly to keep camera binding isolated.

Unexecuted missile-defense references call original `_tickMissiles`,
`hitMissile`, `_castEffect` and the shared `_samBlast` arrival path. Native
hologram attraction retains strict full-height distance, stable insertion ties,
TTL-before-attraction, dead-original-target attraction and permanent loss.
Phase wins near-fuse checks and preserves the original one-step guided branch
before subsequent straight flight. Front-sector reflection removes the missile
and produces a harmless visual endpoint; it cannot settle blast damage or pay
a bounty. Missile report gates now recheck blindness/EMP and require current
aim without the ordinary heavy projectile grace window. Skill interception
uses reverse missile order, planar radius, fractional radius floor, allied
exclusion and no weapon bounty. Server warheads feed raw captured NPC damage
into the shared blast path instead of acquiring hero weapon modifiers.
Active drone-owner kamikaze attack carriers override hologram attraction using
the original pre-redirect owner, unrestricted full-height nearest distance and
stable ties. Native owner carrier IDs replace only the source squad container;
carrier lifecycle and arrival still use their existing authority paths.
Prepared ENet/WebSocket defense scenes exercise hologram redirect, phase loss,
active carrier redirect, reflection events and harmless removal; they have not run. These changes do
not establish final report, source timing, latency or visual-effect parity.

Unexecuted aiming-presentation references evaluate original `_skillVictims`
and `lockGlow`. Native skill lists retain planar range-plus-tolerance,
source radius fallback, target-side rules, roster order and hidden/dead/
garrison/neutral exclusion without adding LOS or vertical gates. Every
currently authored skill has self targeting or zero preview range and thus
retains the original empty skill list. Additional original-helper inputs
exercise the positive advisory path without enabling unsupported gameplay.
Accepted cast metadata captures its definition, point and deadline, including
attack presentation windows; interruption, death, respawn and deadline expiry
remove the preview. Only the requesting peer receives its footprint.
Independent pooled cyan sprites reuse the existing native footprint renderer.

Confirmed native lock presentation uses the target faction, captured mesh
dimensions, source halo pulse/size and a four-segment ring exported from the
original geometry. The halo remains depth independent while the ring tests
depth. Hidden/dead/freed targets and cleared anchors remove it; repeated
packets reuse geometry. Accepted hurt feedback starts the original 200-ms
flash envelope on the local presentation clock. Authority servers allocate no
lock/skill presentation nodes. Prepared transport scenes cover private rosters,
independent clearing and hidden-target removal. Source graph/fixture generation,
compilation, native/render/runtime checks and all transport runs remain deferred.
Immediate source client impact-prediction timing, siege locks and complete
aiming/body/status interaction remain pending.

Authority-confirmed lock events now carry the original pilot/target-pilot
identities. A locked pilot receives its warning even when the attacker is
outside its visible actor roster. Native HUD expiry uses the original
`LOCK.WARN_S` on the local clock, with own-lock event precedence and heartbeat
renewal. Neutral/garrison targets and super/third mutual-neutral locks reject
before confirmation. Original event/HUD and additional `heroLock` gate
references are prepared; incoming-warning transport coverage remains unexecuted.

Current source data explicitly sets `SQUAD.N = 1` and `SQUAD.DMG = 1`. All
regular hero chassis therefore have one player body; legacy formation/follow,
wing salvos and manual body-swap paths have no additional-body producer in the
current roster. Do not revive three-body squads or the removed `heroKamikaze`
saturation attack. Active `kami` actors come from `_launchAtkCarrier` and remain
separate from primary hero bodies. Complete single-body/frame-order, campaign/
boss/super lifecycle and populated match validation still require integration.

Automated tests cover source-derived numerical contracts, authority rejection,
purchase eligibility, lazy magazine refill, duplicate fire/lethal handling,
respawn, source tower/lane subset data, and separate-process ENet/WebSocket
sessions. Runtime/render smoke checks exercise project loading and a populated
battle. Native world checks cover every map/team-size resource against the
original terrain vertices and triangle indices, physical ground-ray reference
samples, layered deck selection/undersides, tunnel floors/roofs/open approaches
and player support at triangle seams under source gravity. The maximum accepted
height error is 0.01 metres; current observed error is recorded in
`tests/validation.json`. Bridge endpoint tolerance and slab/roof dimensions come
from source seams. Overlapping tunnel floors are additionally queried in
isolation; support checks use the assembled world.

Combat reference fixtures evaluate the original `BattleSim.heroPlasma` target
selection for all four tiers of each fan weapon: 384 cases cover front/rear
screening, equal-distance insertion order, building caps, off-axis surfaces,
vertical body spans, upward/downward aim and per-bin range boundaries. They
isolate geometry and per-bin base damage from pending status/evasion mechanics;
native vector rounding allows one part per million in damage. Another 60 source
cases verify planar sight boundaries, the hero aiming bonus and LOS sample
heights. Source box/roof ray references cover both faces, openings and rotated
boxes. These synthetic obstruction checks do not establish scenery import or
complete environmental LOS equivalence.

Projectile references execute the original `_armSpread`, `_guidedLaunchVel` and
`_updateBullets` methods with cached source Three.js vectors, confined to the
offline importer. All four tiers of nine guided/FNF weapons contribute 432
launch vectors and 336 flight sequences, including guided-launcher AA speeds.
Native sequences preserve gravity,
height-dependent climb, radial guidance distance, bounded steering, frozen
laser points, pursuit outside launch range, last-known points, swept proximity,
collision-before-range/fuel precedence and permanent dud state. Synthetic
collision callbacks isolate flight laws; they do not certify source visual-mesh
collision or complete lock acquisition. Vector tolerance is 0.001 metres;
observed accumulated error is recorded in `tests/validation.json`. Another 120
source `_blast` cases verify horizontal target surfaces and vertical body bands;
18 more verify friendly blast eligibility. Those body-band fixtures isolate
evasion, status and structural layers; layer fixtures are described below.

All four tiers of four unguided launchers add 352 source `_lobAim`/`_lobLadder`
controls and 96 complete `_updateBullets` flights. Native Jolt queries replace
the fixture's analytic ground planes and boxes. Cases cover the 45-degree
variable-speed ground solution, steep/no-solution fallback, low-solution charge
ladder, crosshair-only AA selection, sloped range clamps, unsafe-clamp refusal,
adaptive arc point limits, honest radial range and long-lived duds. Native
collision vector tolerance is 0.01 metres; observed error is recorded in
`tests/validation.json`. Persistent scalar integration retains source double
precision; only the native collision/presentation boundary uses Vector3.
Another 80 original `heroBurst` cases verify the strictly bounded planar
minimum-safe-range decision at float32-representable physics endpoints.

All four tiers of 23 flat gun/slot definitions add 828 original `_updateBullets`
sequences against native Jolt ground/box/body proxies. Cases verify gravity,
radial termination, the 0.3-metre segment extension, collision-before-range
precedence, first-body screening and penetration ignoring bodies until its
static collision/range endpoint. Flat rounds terminate immediately at their
boundary; they never inherit explosive dud/fuel lifetime. Beam and rail remain
instant according to the original trajectory classification.

All four tiers of 14 line weapons add 1,568 original `heroLance`/`_lanceHits`
selection/damage cases. They preserve planar north-positive zone coordinates,
vertical-body bands, vertical-axis degeneration, endpoint overflow, stable
equal-distance insertion order, independent zone budgets, the exhausting hit,
per-zone rank/rehit attenuation and honest range filtering after budget usage.
A paired control proves an out-of-range tower still shields an otherwise
eligible hero. Environmental gates, crit and status are isolated; scenery mesh
collision and full defensive effects are not certified. Another 98 `_altRange`
cases verify matching absolute hero/relative NPC height frames and range-modifier
expiry. Three original impact-report entry points additionally verify rejection
of a dead shooter. Recorded vector/damage errors and tolerances are in
`tests/validation.json`.

Authority integration verifies delayed damage, single ammo/power spending,
duplicate-launch rejection, shooter movement/aim changes, chase beyond launch
range, frozen laser points, last-known pursuit after loss of team sight,
thin-wall sweep collisions and surface rejection before spending. Lob checks
also cover preview/launch identity, delayed ground damage, private preview
snapshots, native arc visibility, close self/allied damage and no friendly
bounty/score, including original `_kill` core outcomes for both factions.
Kinetic checks cover firing-origin/direction retention after shooter movement,
first-body screening, deferred front/rear penetration settlement, duplicate
impact suppression, thin-wall and instant-line obstruction endpoints, and dead
shooter rejection while a living ally keeps the target visible.
ENet and WebSocket separate-process checks transmit the actual
packed arc and physical shot events, with no MTU warnings. A populated native
map's lob HUD/arc is additionally rendered and inspected. These synthetic
trajectory checks do not certify every battlefield obstruction or source model
center/mesh collision. Native authority captures weapon tier at launch and owns flight
through impact; source client impact reports and their timing are not replayed.
Launch spread has its own deterministic RNG stream, leaving settlement RNG
unchanged. Snapshot shot events show the swept flight segments; complete
projectile meshes and explosion VFX remain pending.
Kinetic ENet/WebSocket fixtures also verify light-round flight segments and a
heavy-round termination event from separate processes.

Acquisition references execute the original `_coneAcquire`, `_aimTarget`,
`_altRangeTo`, `_effRange`, `_maxRange`, `_tickLock` and `heroLock` seams.
There are 48 default-cone cases, nine fire-control/exact-ray/cone priority cases,
2,560 launch ranges covering both slots and four tiers of all 32 pilots,
36 unique in-flight round-robin choices and 56 authority confirmation cases.
They cover stable angular ties, valid-anchor retention, hero-only fallback,
hidden/dead/friendly rejection, full-centre range, obstruction tolerance,
absolute hero/relative NPC height frames, near-surface fan range, lock TTL and
the exact aim-release flight window. The original `flightCapS` is imported
directly; recovering it from chase fuel would round the inclusive boundary.
Launch range scalar tolerance is 0.0001 metres. Live range modifiers continue
to apply to authority settlement, preserving the original client launch rule.

Native integration verifies off-ray FNF and instant-beam acquisition, fresh
launch selection after turning away, quarter-second throttling, heavy lock
continuation after aim release, expiry, failed lob-control refusal, non-terrain
obstruction and independent authority LOS rejection, private lock snapshots,
and physical FNF/flat rounds capturing the target-dependent launch envelope.
Cone obstruction queries exclude terrain, as the original `_obstHitT` does;
confirmation LOS still queries all native static collision. Native acquisition
uses source spawn-time measured visual centres. Muzzle placement,
touch/view-lock NDC lists, reachability glows, blindness and
neutral factions remain outside these checks. Lock confirmation is authority
local rather than a replay of source client lock messages.

Reachability references execute the original `_reachable`, `_shotWarn`,
`_lobLadder` and `_arcTrace` seams. All 32 pilots' two slots and four tiers
contribute 2,744 cases covering near-surface range, altitude envelopes, ray
clearance tolerance, blast-core coverage behind obstructions, ground/AA arcs,
charge reduction, absent real solutions and arming/minimum-range warnings.
Native arc references use Jolt ground/box queries; ray references isolate
source clearance and core-distance decisions with synthetic obstruction cuts.
The advisory solver shares the launch fire-control ladder, with the source
target-radius tolerance and no best-effort arc when no real solution exists.

Private authority snapshots drive target-specific HUD status for direct/blast
weapons without consuming ammunition, power or either RNG stream. Fan/line
weapons retain the source rule with no single-target entrance gate; weapon
footprints are described below. Native integration and separate-process
ENet/WebSocket checks cover clear/warning transitions, HUD text, global-snapshot
privacy and hidden-target removal. Flat rounds and frozen laser points require
an exact-ray target for advice; cone acquisition cannot promise a physical hit.
A populated native map's status is rendered
and inspected. Native advice now uses source gun-local ports composed with the
source FPV camera, source measured visual bands and authority hit radii.
Moving-target hit
prediction remains pending. Native confirmed-lock and skill glow paths now
have unexecuted source references, described above.

Model-centre references execute the original `makeUnit`, `_spawnUnit` dimension
block and `_entAimPoint` offline with the source cached Three.js modules.
There are 168 translated centre cases for all 32 pilots, both factions of the
eight mercenaries and both factions of eight standard NPC/structure kinds.
Measurements preserve source outline/weapon geometry, combined morph forms,
and team-ring/presentation-effect exclusions. Every loaded source module is
hashed in `data/provenance.json`; the native runtime reads only saved scalars.

Native integration retains spawn-time centres across rotation and morph flags,
uses them for cone acquisition, AA lob aim and target reachability, and verifies
an angular-boundary case where the old cylinder midpoint incorrectly rejects
the original centre. ENet/WebSocket private advice also targets a mercenary
whose measured centre differs from its authority cylinder midpoint. Neither
authority target volumes nor balance values are retuned. Animated visual-mesh
collision, full native pose/attachment rendering, TPS/bot mounts, boss/super
scaling and complete animated visual-mesh envelopes remain pending.

Weapon-footprint references execute the original `_shotVictims`,
`_lancePierced`, `_inShotRange`, `_reachable` and `_bodyDy` seams. All 32 pilots'
two slots and four tiers contribute 4,820 cases: 1,624 direct, 1,156 blast,
1,400 line and 640 fan cases. They preserve the no-reticle fan/line entrance,
nearest-per-bin screening and stable ties, source 3D perpendicular line sections,
endpoint caps, independent penetration budgets and post-budget visibility/range
gates. Controlled proxy geometry isolates selection; penetration fixtures retain
the original `lancePenCost` values. They do not certify animated visual-mesh hits.

Blast footprints consume visible enemy body bands after one shot gate, without
adding victim LOS, launch-range or structural-layer checks. Source `_reachable`
reuses `_rgAim`, so a reticle unit overwrites the blast footprint's impact with
its measured centre; a dedicated paired-surface case preserves this behavior.
Lob footprints reuse the cached fire-control impact/aim and whole-shot warning;
obsolete control position, direction, clock or weapon tier rejects the preview.
These client advisory lists remain separate from authority damage settlement.

Private snapshots drive native additive, depth-independent billboard glows.
The importer executes source `glowTexture`; source size, colour and opacity
seams supply shared resources. Glows pool/reuse nodes, skip a confirmed anchor,
clear in the shop, and remove hidden/dead/freed victims. Native checks cover
blast coverage behind a wall with shared team sight, front/rear penetration,
independent fan bins, cached lob controls, privacy and no resource/RNG spending.
ENet/WebSocket checks transmit an actual two-victim roster, normal/warning
materials, shop clearing and hidden-target removal; a populated native map's
two glows are rendered and inspected. TPS/super/recoil camera behavior, source visual-mesh
ray endpoints, moving-target prediction, siege locks and full status/environment
interactions remain pending. Skill footprints and confirmed-lock glows now have
native paths and unexecuted references, described above.

Cockpit references execute the original `_buildCockpit`, `_syncCockpitWeapon`,
`_cockpitEmission`, `_selfMuzzle`, `_reloadAnimOffset` and gun-root render-tick
block offline. All 32 source model graphs become compressed native scenes with
1,400 mesh nodes, source vertices, material groups, local transforms, procedural
textures and reversed native front-face winding. Native checks compare each
mesh's transformed bounds against original Three.js bounds within 0.0001 metres,
plus topology and sampled original vertices. There are 184 indexed rest muzzle
cases, including both morph forms and the source no-cloned-emitter fallbacks;
these capture original gun-local positions rather than inventing body offsets.

Another 5,376 source poses cover both slots and all four tiers, reload progress
clamps, kick/pull limits, positive/negative lob angles and rotation around the
measured weapon pivot. There are 640 aim/FOV/morph visibility cases at the source
0.1-degree return threshold, and 25 barrel-elevation boundary cases. Native
presentation reads authoritative reload deadlines, accepted-fire feedback and
private fire-control elevation. Only the bound local camera allocates a cockpit;
dedicated and remote actors keep no FPV geometry. Presentation cannot refill
ammunition, settle damage or consume either combat RNG stream.

Separate-process ENet/WebSocket checks verify accepted light/heavy feedback,
reload pose, private lob elevation, zoom hiding, death hiding and absent server
cockpit allocation. Four populated-map renders (two robot and two morph pilots)
are inspected. These fixtures certify rest geometry and gun-root pose,
not world visual-mesh hits or full toon/outline appearance. Dynamic weapon
presentation references are described below. Scalar source gun ports now drive
combat launch/query origins. Authority pose/clock, immutable shooter height
frames and the remaining world camera/body placement boundary are described below.

Weapon-presentation references execute original `_markFire`,
`fireReferenceWeapon`, `stepCombatFx`, full `stepLocomotion`,
`_syncCockpitWeapon` and the FPV flash render block. Forty endpoint-form
sequences (all 32 pilots, including both trees of eight morph pilots) contribute
1,456 complete frames with variable frame intervals, alternating slots, barrel
wraps, two distinct rounds in one clock tick and repeated immutable events.
Native source-node mirrors match original position/scale/quaternion within
0.00001; they preserve the parent-name translation gate and active-rig lookup.
Both morph sequences advance on each event even when one tree is hidden.

Forty-seven imported source clip tracks become native Animation value tracks.
They override procedural receiver recoil before payload omission/restoration
and the finger/tuft post-pass, preserving the original ordering. Event-relative
decay remains independent of frame rate. Three source slots have no cloned
emitter; `_muzzle.copy()` can mutate their shared fallback vector after switching
slots. Native caches retain those aliases, with current-emitter flash positions
compared on every reference frame rather than replaced with constant offsets.

Another 36 source flash cases verify the 0.045-second lifetime, heavy size,
independent random samples and inclusive expiry. Native additive materials
retain source depth-test/depth-write flags. Aiming hides parts while retaining
the flash. Authority feedback carries a per-pilot serial and accepted clock;
duplicates/older serials cannot advance barrels or restart effects. Integration
also rejects non-finite presentation times and verifies no presentation damage,
ammo refill or combat/spread RNG consumption. Separate-process ENet/WebSocket
checks now receive the actual serial-driven sequence and flash. Three additional
accepted-fire renders cover finger, payload and no-cloned-emitter weapons.
Burst muzzle/impact particles and body/view reaction, continuous morph/body pose, full status interactions, TPS/super/recoil
camera behavior, visual-mesh collision and final shaders remain pending.

Authority weapon-pose references execute the original `_selfMuzzle`,
`_cockpitEmission`, `_markFire`, `_syncCockpitWeapon`, complete weapon animation
steps and gun-root render block. All 32 pilots contribute 48 sequences, 1,732
frames and 628 pre-fire ports, including both morph endpoints and repeated form
switches. Imported scalar transform paths reproduce the ports without allocating
FPV meshes or scene nodes on the authority. Variable intervals, simultaneous
distinct events, next-barrel selection before animation advancement, reload
clamps, elevation, recoil and shared fallback aliases retain source ordering.
Port tolerance is 0.0001 metres; maximum observed error is 0.000008534 metres.

Private snapshots carry the simulation clock, serial, slot, form, gun transform,
recoil and current port. Local gun recoil follows this clock, so repeated render
frames cannot decay it twice. Accepted-fire feedback carries the pre-fire next
port. Global snapshots omit private pose state, dead pilots clear it, and stale
clocks/events reject without mutating sequences or aliases. Authority death
ticks keep recoil decay running. Pose calculation cannot spend ammunition, power
or either combat RNG stream; dedicated servers keep no cockpit geometry.

All physical player rounds capture immutable body position, relative altitude,
absolute hero eye and relative sight height at launch. The existing 98 original
`_altRange` cases additionally verify those frames after shooter movement and
with a distinct muzzle origin; live range modifiers still apply at settlement.
Native rooftop checks preserve the source terrain reference separately from the
physical launch surface. Kinetic direct/line settlement uses the captured height
frame, and direct missile interception uses its captured relative body position.
ENet/WebSocket checks carry actual native pose transforms and accepted ports,
bind the private pose to the local cockpit and verify death/privacy behavior.
These checks establish the authority prerequisites; gun-local FPV origin
adoption is described below.

Muzzle launch references execute the original complete `_tryFire` method with
source cockpit ports, `_resolveAim`, `_selfMuzzle`, `_lobAim` and launch laws.
All 32 pilots, both slots, four tiers and both morph forms contribute 960 cases,
including 552 physical launches. Current-port advice remains distinct from the
next-barrel launch sample. Reticle and acquisition rays stay camera-based;
flat rounds leave the muzzle along camera forward, frozen laser points retain
the reticle endpoint, and instant lines connect muzzle to that endpoint.
Reload/recoil/elevation roots and native Jolt plane/wall queries exercise the
whole source launch seam. Maximum observed position/velocity vector error is
0.000068240; position tolerance is 0.0001 metres, velocity/reticle tolerance 0.001.
Visual effects, audio and burst echoes are stubbed in this launch oracle; it does
not certify complete source recoil/charge timing or impact reports.

Another 2,200 original `terrain.surfaceAt` cases verify registered terrain,
reachable stacked decks, low bridge boarding, covered tunnels, open approaches
and exposed roof selection at the muzzle. Native physical support must still
exist before launch spending. The sampler handles ports below verified terrain
without replacing missing ground. Scenery rooftops and frozen water remain
outside this registered-layer fixture. Fan and line settlement keep target body
bands in relative source frames while static collision queries remain in the
native world frame. Shooter eye/range state remains separate from muzzle height.

Native integration verifies accepted-port/physical-origin identity, a narrow
wall blocking the muzzle while clearing the reticle, preserved flight after
shooter movement/turning and advice that cannot mutate fallback aliases.
ENet/WebSocket transport checks now match the first actual heavy flight segment
to the accepted port and retain private lob origins. All existing transport
fixtures pass, and the populated lob arc/HUD is rendered and inspected.
These checks now compose source gun-local geometry with source `heroView` FPV
anchors, described below. Continuous morph poses, TPS/super/recoil camera
behavior and TPS/bot body mounts remain pending. They do not establish complete
source world muzzle placement or animated visual-mesh hits.

FPV camera references execute original `heroView`, `selfH`, `_eyeH`,
`_cameraDeClip` and `_cameraPullSegment` seams. All 32 pilots contribute 576
anchor cases across ground/air, yaw and crouch inputs; 54 clipping cases cover
expanded circle/rotated-box skin, inside/tangent/parallel boundaries, vertical
rejection, below-deck filtering, dynamic obstacles, 3D cuts, ridge samples and
non-finite surfaces. Maximum observed vector error is 0.000003815 metres against
a 0.0001-metre tolerance. The camera's original 0.5-metre near plane is retained.
Crouch inputs certify the camera formula only; the new charged-jump gameplay
implementation remains unverified.

Authority reticle/cone/launch queries, absolute hero-eye height frames and local
rendering now use the original eye ratios and body-forward offsets. The flight
eye sits at body height zero and keeps its source nose offset. Camera de-clipping
uses registered source column bounds, native non-terrain/non-slab collision and
the shared registered-layer surface sampler. Per-physics-frame pose caches
avoid repeated queries, invalidate on pose changes and cannot spend ammunition,
power, HP or combat/spread RNG. Body motion remains separate from camera pullback.

Snapshots retain clipped offsets in the body's yaw frame, including a valid
zero offset, while replicas interpolate body position/heading. Native tests
verify authority/render origin and orientation, replica identity and a thin-wall
pullback. Separate-process ENet/WebSocket checks verify ground-to-air-to-ground
camera offsets, source near-plane values and actual camera binding; all existing
transport fixtures pass. Three populated native FPV accepted-fire renders are
inspected. The 960 complete launch cases now begin at original uncharged FPV
anchors, including hover-height flight forms and original camera pullback.
Full geographic blockers, dynamic obstacle producers, TPS/super scaling and
view recoil/roll/shake remain outside this fixture.

Burst-presentation references execute original `fireBurstN`, `fireBurstGap`,
`_queueBurst`, `_tickBurstFx` and `_burstEchoSelf`. All 256 weapon definitions
contribute 513 queue sequences and 1,594 steps, including exact inclusive
deadlines, repeated ticks, backward insertion order after a hitch, mixed batches,
captured tiers and consumed callback failures. Exact boundary probes reconstruct
native deadline arithmetic to avoid a one-ULP JSON decimal conversion difference;
the runtime retains the original comparison without an epsilon.

Another 48 source sequences cover all pilots, both morph endpoints and switching
forms across 1,732 complete frames. Target queries and view/body recoil are
isolated in this pose oracle; the original echo still selects the next actual
gun port before marking fire and refreshing recoil/flash. Source mirrors,
fallback aliases, current ports and subsequent accepted launch ports match within
0.0001 metres (maximum vector error 0.00002398 metres). Separate acceptance and
presentation serials preserve immutable-event deduplication after echoes advance
the barrel sequence. Death consumes due self echoes without marking fire.

Native authority keeps only this scalar bookkeeping; local FPV presentation
shares the schedule and source flash lifetime. Integration and separate-process
ENet/WebSocket tests verify one damaging round and one ammunition/power spend per
accepted shot, no echo combat events or combat/spread RNG use, slot/tier capture,
private pose serials, duplicate rejection and the next accepted shot. Two native
echo-flash renders are inspected. Source projectile and thin-tracer presentation
references are described below. Muzzle/impact particles, remote/TPS/body mounts
and view/movement reaction remain explicitly unimplemented; scheduling/pose
certification does not establish complete burst visual or recoil equivalence.

Projectile-presentation references execute original `projectileMesh` and
`stepProjectileFx` with the actual combat asset registry. All 32 pilots, both
slots and both faction palettes produce 128 native scenes and 222 mesh nodes.
Native graph transforms, bounds and vertices retain the source geometry; 3,200
age/speed cases compare authored opacity pulses, wake scaling and jet flicker.
The shared scene importer preserves source material groups, alpha/depth flags
and winding. Outline shells remain excluded until their shader is implemented.
Each live opacity animation owns its material while mesh resources are shared.

Another 1,024 cases across all weapon tiers execute `_spawnVisShell` and
`_updateVisShells` for 22,628 frames. Native pure presentation preserves launch
speed overrides, launcher AA/45-degree priority, launch lift, frozen visual
targets, ride guidance, gravity, target-sphere range limits, the small-segment
collision gate and collision-before-range termination. Maximum combined
position/velocity vector error is 0.00006292 within the 0.001 tolerance. Native
static sweeps stop at thin walls; range expiry silently recycles the model.
Fourteen original `_tracer`/`_updateEffects` cases verify endpoints, linear fade
and inclusive expiry. Accepted FPV light beams/rails and echoes share this thin
tracer and the original weapon/faction colors.

Accepted physical rounds retain a stable presentation identity and captured
weapon profile. Owner-only snapshots bind native meshes to authority position,
velocity and age; global/dedicated views allocate no player projectile models.
Local authority rendering updates those poses each frame. Actual cockpit echoes
emit source meshes/tracers into a separate pool and cannot spend HP/ammunition/
power, append combat events or consume combat/spread RNG. Duplicate/stale fire
events remain governed by the independent acceptance serial. Native tests verify
material isolation, variant reuse, snapshot clearing and unused-terrain queries.
ENet/WebSocket tests verify light/heavy models, moving poses, echo emission and
clearing. Their slowed flight clock isolates transport binding, so these checks
do not certify fast-shot latency or client interpolation/prediction. A four-model
native gallery render is inspected. Remote/TPS/body mounts, full geographic
collision, source world muzzle/impact particles, heavy beam/fan effects and final
shader appearance remain pending.

Server missile references execute `_tickMissiles`, `hitMissile`, `heroLance`,
`_tickBaseGuns`, `_acquireTarget` and `_frame`. Eleven flight sequences cover
guided movement, permanent range loss, fuse-before-range and TTL-before-fuse
precedence, target death/disappearance, endpoint obstacle blasts and harmless
expiry. All 32 pilots' two slots and four tiers contribute 2,048 single-body
damage/range/bounty cases; 448 line cases cover missile-centre cylinder geometry
and endpoint caps. Six dual-gun sequences verify independent cooldowns and
launch parameters; ten acquisition cases verify planar centre range, hero bias,
stable ties and air ceilings. The inclusive native ceiling allows 0.001 metres
of standing-surface ray error. Five snapshot cases preserve HP ceiling and the
source north-positive JavaScript half-tie quantization.

The offline importer evaluates the original `projectileMesh` geometry and
initial `stepProjectileFx` transforms with cached Three.js. Native shared
ArrayMesh/concave StaticBody3D parts provide visible missiles and physical shot
queries; 24 original mesh rays verify initial native hit presence/endpoints
within 0.001 metres. Full toon/outline shaders, animated tail geometry, source
snapshot interpolation and damage-stage effects remain pending. This initial
geometry fixture does not establish complete animated visual-mesh equivalence.

Authority integration verifies delayed dual-gun launches, global missile
snapshots, instant/kinetic/terminal-line interception, single launch spending,
friendly missile screening without cone fallback, independent unit penetration
budgets, one bounty without score, and harmless removal. The shared missile
blast path accepts dead/removed launchers in an active match and settles bands in each target's relative standing
frame, including heroes on different deck heights. Terrain/slabs do not stop
these server missiles; native columns/walls still trigger endpoint blasts.
Interception does not turn player FNF/lob warheads into shootable missiles.
The earlier verified fixtures exclude decoy attraction, phase/reflect defenses,
blindness/jamming, wing-body salvos, ability interception and complete source
impact reports. The newer unexecuted missile-defense references are described
above; they do not extend these saved validation results. Native AA-ambush
producers are written but still require final populated verification.

Separate-process ENet/WebSocket fixtures exercise actual base launches, native
client geometry/HP snapshots, normal fire commands, interception events and
bounty replication, without MTU warnings. Their paused flight fixture isolates
transport and interception; it does not certify moving-missile latency behavior.
A populated native map's source-derived missile body is rendered and inspected.

Structural references execute the original slab uploader, `_ingestSlabs`,
`_slabSep`, `_unitLev`, `_blast`, `makeDeckIndex`, `makeTunnelIndex` and player
support-classification block. They cover 1,500 separation cases, 1,250 entity
levels, 1,500 client support poses and 136 friendly/enemy damage cases. All 90
native worlds receive accepted source ribbons, preserving uploader rounding,
width limits, slab caps, insertion order and north-positive gallery masks.
Queries distinguish human support levels from inferred bot/NPC levels, retain
structure level zero and airborne tunnel clearance, and preserve lowest-floor
open-approach precedence and rooftop terrain references.

Bridge blasts separate levels only inside the same ribbon; side overflow
remains eligible. Tunnel portals permit sight but block cross-layer blasts;
only an open gallery-side exit passes, and any overlapping closed ribbon vetoes
it. Native authority checks exercise actual bridge and tunnel warhead impacts,
relative body bands, support rays, friendly coverage, SAM target-level fuses and
the deliberate absent-level bypass for missile obstacle blasts. Player warhead
impacts report tunnel level two or level zero, never bridge level one, matching
the source rule that keeps bridge structures eligible. These fixtures isolate
status/evasion and do not certify full traversal or source report timing.

Authority integration checks verify fan blocking, deliberate blast coverage,
shared living observers, hidden shot filtering, host hide/reveal transitions,
and continued simulation of hidden actors. Terrain/road collision is native;
legacy source obstacle grazing tolerance and full weather/skill vision remain
pending.

Vertex colors retain source values within native RGBA8 precision. With imagery
omitted, the baker invokes the original missing-imagery color ladder rather
than exporting a blank texture. Structure and hero standing surfaces are
checked across every preset/team-size combination.

World baking preserves the original terrain and road-generation blocks, not
the complete biome builder. These checks do not certify all geographic scenery,
LOS, full-map traversal, complete abilities, full-match balance, campaign
progression or mobile deployment. Lane heights seed native paths; the complete
source NPC surface-following policy remains pending.

## Implementation order

1. Preserve source geometry and target-volume semantics using imported terrain
   resources and native collision; establish map/LOS/traversal parity fixtures.
2. Finish projectile flight: guided/FNF and lob flight laws, native sweeps,
   source ground fire control/charge ladder, launcher AA selection and flat gun
   flight/terminal planar penetration, default cone acquisition/hysteresis,
   authority lock lifecycle, target-dependent launch ranges, base missile flight
   and direct/kinetic/penetrating interception, structural blast-layer separation
   and rooftop height references are in place. Source target reachability
   decisions and private HUD status use source spawn-time measured model centres.
   Source weapon-footprint rosters and pooled native range glows are in place.
   Source FPV rest geometry, indexed ports, gun-root poses and visibility are
   also verified and rendered natively. Source weapon-binding mirrors, visual
   barrel progression, fallback-cache aliases and muzzle flashes are in place.
   Scalar authority pose/clock, private recoil presentation and immutable shooter
   height frames are in place. Source gun-local ports now drive launch, fire
   control, reachability and footprint origins. Source `heroView` FPV anchors,
   registered-obstacle de-clipping, near plane and replica offsets are in place.
   Source burst scheduling, echo barrel/recoil/flash poses and separate accepted
   and presentation serials are in place. Source projectile scenes, opacity/tail
   animation, private owner poses and FPV echo shell/thin-tracer flight are in
   place. Confirmed-lock and skill presentation now have native implementations
   and unexecuted original references. Next finish visual-mesh envelopes,
   source impact/report semantics and remote/heavy presentation, then complete
   aiming/body/status integration.
3. Implement the complete ability matrix, status/shield/evasion behavior,
   carriers and summons with source simulation reference fixtures. Core status,
   non-carrier effects, cast/charge lifecycle and dedicated flight power are
   implemented with unexecuted source oracles. Clone, autonomous summon and
   hologram lifecycle/settlement, source graph export and prepared references are
   now in place. Point carrier launch/flight/arrival/interception, native scene
   export and prepared original references are in place. Next finish remaining
   decoy/support fields, source aiming/lock presentation,
   climate/attraction/animation integration and full special-entity interactions.
   Cube/fog authority rules, native geometry and unexecuted source references are
   in place. Retain the
   final verification deferral until the complete implementation is ready.
4. Source wave/economy rules and full bot decision/resource paths are written
   with prepared original references. Finish combined frame order, native
   traversal and mode integration, then compare seeded complete matches.
5. BOSS/assault authority progression, campaign deployment/dialogue/progress and
   native HUD/cinematics have prepared source references and map generation paths.
   Super settlement/deployment/shop and original references are now written.
   Finish full environment/body presentation and native UI controls;
   generate campaign resources and certify complete chapter lifecycles in the
   final validation phase.
6. Verify platform exports, transport failure/recovery and production hosting.

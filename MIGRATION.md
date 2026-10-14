# Feature parity ledger

This ledger distinguishes imported source content from implemented native
behavior. A passing math fixture does not establish full match equivalence.

Current status/ability/movement/companion/carrier/NPC/economy/wave/weather/environment/scenery/field-threat/loot/supply/camp/civilian/match-stat work is unverified. At the user's request,
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
| Movement | Native authority physics and source spawn positions/headings; charged jump, automatic morph launch/landing, lift budgets, hover/altitude bounds, damage-proportional sinking, source shallow/full/frozen immersion, marine tide lift reference and ice floor/ceiling constraints are implemented but unverified | Complete source integration/order, slope support, climbing, complete surface/hazard effects, recoil movement and traversal certification |
| Combat math | Verified RNG, shield overflow, range/falloff, fan/line/blast geometry and target volumes; evasion, suppression, directional defensive shields, critical modifiers and elemental statuses are implemented but unverified | Final source-oracle/integration verification; complete environmental and special-entity interactions |
| Weapons | Authority ammo, reload, fire cadence and native hit queries; source beam/rail instant attacks; source 3D fan body spans, per-bin nearest targets, deterministic ties and building caps; team-vision/LOS gates for direct, fan and line attacks; intentional blast coverage retained; guided/FNF flight with launch spread/climb, guidance distance, fixed laser point, chase fuel, swept proximity and native segment collision; launcher crosshair AA selection; 45-degree ground lob, low-solution charge ladder, terrain clamp and private authority arc preview; flat gun flight with first-body direct hits and terminal planar penetration settlement; hero-only acquisition cone, confirmed-anchor hysteresis, target-dependent launch ranges, quarter-second authority lock checks and in-flight FNF continuation; base missile flight and interception by instant, kinetic and penetrating attacks; source bridge/tunnel/gallery blast-layer separation and rooftop height references | Complete muzzle/model-centre and reachability envelopes, full status/buff interactions, missile decoy/phase/reflect behavior, ability interception, recoil and source-specific reports remain pending |
| Abilities | Source cast channels, squared interruption fractions, independent charges, buffs/heals/auras, EMP/CC, stealth/alpha, rally/revive/recon, interception, reflection, phase exit, shield bash, siege mode, tactical fog, six-panel cube fields, clones, autonomous summons, holograms and point-delivery carrier flight/arrival/interception are implemented but unverified; source scene export/packing and original oracles are prepared | Other special/support fields and full interactions; source carrier/companion model generation, climate and NPC targeting, skill lock/presentation, owner disconnect cleanup and populated transport/render verification; unsupported paths reject before spending resources; final source/integration verification |
| Economy | Eight tracks, source remote/dead purchase eligibility, shared lane creep upgrades, permanent damage assists, bounded score, bounty modifiers, death penalties, scene salvage/cash/ammo/affix loot, timed airdrop rewards, civilian aid and civilian/spy kill credits are implemented but unverified; battery overcharge/charge deadlines and item/skill healing source gates are written | Balance preferences, full shop/campaign eligibility integration and final purchase/death/assist/loot/supply/civilian verification |
| Waves/NPCs | Source compositions, ordered prefill recipes, mirrored spawn jitter/floors, planar progress, wave cohesion, control/push rules, 8 Hz NPC stepping and dual base missile guns; NPC target gates/priorities/cache, captured creep damage/durability, per-target blast settlement and AA-ambush producers are implemented but unverified | Native traversal/support and weather integration, complete squad body rosters and complete NPC tick/transport verification |
| Camps/civilians | Source camp sampling/rosters, garrison healing/protection, tether/aggro movement, bunker/member respawns, first-clear liberation, civilian/spy seeding, follow/away/wander/aid/death/respawn rules and private spy identity are written; camp obstacle clearance and native G/H interaction are implemented but unverified | Per-ID civilian mesh/centre variation, rig animation/marks, full geography/building visual clearance and populated render/transport/integration verification; source companion resources remain ungenerated |
| Bots | Shared human movement/collision, source reaction/view-angle/turn limits, push/retreat/fire | Source tactical/role/policy AI, alert bearings, error distribution, skill/heavy decisions |
| Match outcome | Authority core destruction, hero respawn and result screen; source faction kills/deaths/paid assists/weighted creep last hits, public snapshots and native HUD rows are written but unverified | Complete per-body/squad/mode statistical integration, damage/leaderboards and replay parity |
| Networking | Shared solo/ENet/WebSocket authority; lobby registration, roster, start, snapshots, disconnect handling; large snapshots use a separate reliable native channel | PIN/discovery, spectators, reconnect/late join, snapshot bandwidth/loss profiling, mobile/Web export QA, production hosting |
| Visibility | Shared planar team sight and source LOS heights; skill pulses, stealth/blind gates, tactical fog sight/protection and cube-plane LOS are implemented but unverified | Full environmental vision effects, source grazing-obstacle tolerance, event audibility and final status/field visibility verification |
| Story | Original narrative/chapter content exported | Campaign flow, boss/siege rules, scene staging/dialogue UI and saves |
| Environment | Source seven-dimensional climate, independent seed, solar/lunar schedules, thermal freeze/thaw history, rain/snow/sand surface state, movement/lift/jump/cadence/reload/cooldown/damage/accuracy effects, probabilistic freeze and entity/scenery lightning/shockwaves are implemented but unverified; native dynamic sky/depth fog/light, precipitation particles and strike flashes; water/swamp classification, marine tides, immersion and proportional frozen-fluid burn; four fire kinds, expiry/quench/DOT and original fire/smoke scene export/animation paths; source hazard/vehicle/mine/AA/relay seeding, lane connectivity, corridor pruning, physical rubble/fire/salvage, flood movement/jumps and mine proximity presentation are written; four seasons/times and eight starting weather choices | Cloud/fog-bank and precipitation detail layers, contact effects, rendered deposits/permanent scorch, complete scenery roster, source damage/cracks/debris, per-entity hazard/fire geometry variation, water waves/shore/underwater appearance and full environmental/render/transport certification |
| Input/UI | Native Chinese lobby/HUD/shop/minimap and weapon advice/glows; F shield stance, held jump input, cast countdown, lift, ability charges, civilian G/H prompts and source-limited supply/loot/relay/threat/civilian notices are implemented but unverified; minimap excludes source neutral actors | Native touch UI, gyro, complete source control restrictions, spectator controls, settings/persistence; full source aiming presentation, confirmed-lock and skill glows, complete combat feed; final HUD/render/transport verification |

## Verification boundary

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
before spending. Full source aiming/confirmed-lock UI, source flight VFX/body
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
Full squad-body coverage and combined missile decoy/phase/reflect behavior
remain pending.

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
replica authority rejection. Full squad body rosters, super/story/mode
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
prediction, confirmed-lock and skill glow visuals remain pending.

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
ray endpoints, moving-target prediction, skill footprints, confirmed-lock glows,
siege locks and full status/environment interactions remain pending.

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
Decoy attraction, phase/reflect defenses, blindness/jamming, wing-body salvos,
ability interception and complete source impact reports
remain outside the current fixtures. Only base guns currently produce this
server-missile family; AA-ambush placement remains unavailable.

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
   place. Next finish visual-mesh envelopes, source impact/report semantics and
   remote/heavy presentation, then
   confirmed-lock/skill presentation.
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
4. Port full wave/economy/bot rules, then compare seeded complete matches.
5. Port campaign/boss/dialogue progression, dynamic environment and UI controls.
6. Verify platform exports, transport failure/recovery and production hosting.

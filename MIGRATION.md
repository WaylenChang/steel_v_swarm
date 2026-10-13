# Feature parity ledger

This ledger distinguishes imported source content from implemented native
behavior. A passing math fixture does not establish full match equivalence.

| System | Native status | Remaining parity work |
| --- | --- | --- |
| Project/runtime | GDScript main scene and autoloads; no runtime JS | Platform exports and delivery builds |
| Character content | All 32 pilots, four weapon/ability tiers, chassis stats | Some mechanics below remain unavailable |
| Art | Original reference/combat/faction glTF and audio imported; native animation playback | Combat attachments, morph poses, full cockpit presentation, VFX, damage states |
| Map layouts | 18 qualified presets, all five team sizes, source lane subsets/tower pairs; 90 native terrain/road resources | Satellite imagery, OSM buildings/facilities, habitat objects, water and hazards; complete geography-service behavior |
| Map generation/services | Verified captures drive offline terrain resources; missing runtime resources reject explicitly | Mixed geographic layers, procedural random recipes, authored story arenas, live source preparation/qualification, cache refresh and relay fallback |
| World | Source terrain vertices/topology/portal holes; graded roads, bridge slabs, tunnels, roofs, gallery openings and columns; native Jolt collision | Full scenery, texture/shader appearance, edge geometry, environmental LOS and complete traversal equivalence |
| Movement | Native authority physics; ground, flight, jump, sprint, explicit morph toggle; source-derived per-seat spawn positions/headings retained on respawn | Charged jumping, automatic morph transitions, flight budget/drain, surface penalties, recoil movement |
| Combat math | Source-fixture parity for RNG, shield overflow, range envelope, falloff, fan bins, planar line body bands, independent penetration budgets and blast body bands; source hero/NPC target volumes and hero ground/air movement cylinders | Evasion, suppression, directional defensive shields and status effects |
| Weapons | Authority ammo, reload, fire cadence and native hit queries; source beam/rail instant attacks; source 3D fan body spans, per-bin nearest targets, deterministic ties and building caps; team-vision/LOS gates for direct, fan and line attacks; intentional blast coverage retained; guided/FNF flight with launch spread/climb, guidance distance, fixed laser point, chase fuel, swept proximity and native segment collision; launcher crosshair AA selection; 45-degree ground lob, low-solution charge ladder, terrain clamp and private authority arc preview; flat gun flight with first-body direct hits and terminal planar penetration settlement; hero-only acquisition cone, confirmed-anchor hysteresis, target-dependent launch ranges, quarter-second authority lock checks and in-flight FNF continuation; base missile flight and interception by instant, kinetic and penetrating attacks; source bridge/tunnel/gallery blast-layer separation and rooftop height references | Complete muzzle/model-centre and reachability envelopes, full status/buff interactions, missile decoy/phase/reflect behavior, ability interception, recoil and source-specific reports remain pending |
| Abilities | Imported definitions; basic buff/heal/self-boost paths only | Carriers, summons, persistent fields, revive, CC, multi-charge timing and full effect matrix; unsupported paths reject before spending resources |
| Economy | Eight tracks, funds + score eligibility, bounded bounty, supply-radius purchase gate | Assists, death penalties, loot, creep upgrades, full shop rules and balance preferences |
| Waves/NPCs | Source compositions, native path sampling, infantry/armor/air waves, structure attacks; independent dual base missile guns with planar centre acquisition, hero bias and air ceiling | Spawn prefill/spacing, creep scaling, complete NPC AoE and target priorities, AA-ambush producers, neutral forces/civilians |
| Bots | Shared human movement/collision, source reaction/view-angle/turn limits, push/retreat/fire | Source tactical/role/policy AI, alert bearings, error distribution, skill/heavy decisions |
| Match outcome | Authority core destruction, hero respawn, result screen | Full statistical ledger and replay parity |
| Networking | Shared solo/ENet/WebSocket authority; lobby registration, roster, start, snapshots, disconnect handling; large snapshots use a separate reliable native channel | PIN/discovery, spectators, reconnect/late join, snapshot bandwidth/loss profiling, mobile/Web export QA, production hosting |
| Visibility | Shared planar team sight and hero aiming bonus; source observer/target LOS heights; side-filtered snapshots and shot events also drive offline/host rendering without removing authority actors | Full environmental vision effects, fog/stealth/blindness, source grazing-obstacle tolerance and event audibility |
| Story | Original narrative/chapter content exported | Campaign flow, boss/siege rules, scene staging/dialogue UI and saves |
| Environment | Native static day/dusk/night sky and fog selection | Dynamic climate, rain/snow, deposits, lightning/fire, source weather gameplay |
| Input/UI | Chinese native lobby, HUD, shop, menu, minimap; basic controller bindings; authority lob arc, AA/charge/blocked status and minimum-range warning; private confirmed-lock HUD status | Native touch UI, gyro, source control restrictions, spectator controls, settings/persistence; full source aiming presentation |

## Verification boundary

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
confirmation LOS still queries all native static collision. Native centres
currently use normalized target-body proxies; source measured visual centres,
muzzle placement, touch/view-lock NDC lists, reachability glows, blindness and
neutral factions remain outside these checks. Lock confirmation is authority
local rather than a replay of source client lock messages.

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
   and rooftop height references are in place. Next implement complete
   reachability/muzzle envelopes and impact-report semantics.
3. Implement the complete ability matrix, status/shield/evasion behavior,
   carriers and summons with source simulation reference fixtures.
4. Port full wave/economy/bot rules, then compare seeded complete matches.
5. Port campaign/boss/dialogue progression, dynamic environment and UI controls.
6. Verify platform exports, transport failure/recovery and production hosting.

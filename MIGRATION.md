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
| Combat math | Source-fixture parity for RNG, shield overflow, range envelope, falloff, fan bins and penetration zones; source hero/NPC target volumes and hero ground/air movement cylinders | Evasion, suppression, directional defensive shields and status effects |
| Weapons | Authority ammo, reload, fire cadence, hitscan and native hit queries; fan/line/blast settlements | Launcher/guided/missile shots currently resolve at ray impact; physical flight, arming, seeking, recoil and source-specific reports are pending |
| Abilities | Imported definitions; basic buff/heal/self-boost paths only | Carriers, summons, persistent fields, revive, CC, multi-charge timing and full effect matrix; unsupported paths reject before spending resources |
| Economy | Eight tracks, funds + score eligibility, bounded bounty, supply-radius purchase gate | Assists, death penalties, loot, creep upgrades, full shop rules and balance preferences |
| Waves/NPCs | Source compositions, native path sampling, infantry/armor/air waves, structure attacks | Spawn prefill/spacing, creep scaling, NPC AoE, target priorities, neutral forces/civilians |
| Bots | Shared human movement/collision, source reaction/view-angle/turn limits, push/retreat/fire | Source tactical/role/policy AI, alert bearings, error distribution, skill/heavy decisions |
| Match outcome | Authority core destruction, hero respawn, result screen | Full statistical ledger and replay parity |
| Networking | Shared solo/ENet/WebSocket authority; lobby registration, roster, start, snapshots, disconnect handling; large snapshots use a separate reliable native channel | PIN/discovery, spectators, reconnect/late join, snapshot bandwidth/loss profiling, mobile/Web export QA, production hosting |
| Visibility | Side-filtered enemy entity snapshots and actor-filtered shot events | Local host render visibility, full environmental vision effects and event audibility |
| Story | Original narrative/chapter content exported | Campaign flow, boss/siege rules, scene staging/dialogue UI and saves |
| Environment | Native static day/dusk/night sky and fog selection | Dynamic climate, rain/snow, deposits, lightning/fire, source weather gameplay |
| Input/UI | Chinese native lobby, HUD, shop, menu, minimap; basic controller bindings | Native touch UI, gyro, source control restrictions, spectator controls, settings/persistence |

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
2. Move projectile flight to native physics and validate all source trajectory,
   arming, seeking, envelope and penetration edge cases.
3. Implement the complete ability matrix, status/shield/evasion behavior,
   carriers and summons with source simulation reference fixtures.
4. Port full wave/economy/bot rules, then compare seeded complete matches.
5. Port campaign/boss/dialogue progression, dynamic environment and UI controls.
6. Verify platform exports, transport failure/recovery and production hosting.

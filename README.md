# Steel vs. Swarm — Godot

Native GDScript migration project for `steel_vs_swarm`. Requires standard
Godot 4.7.2. Import `project.godot` in Godot and press **F5** to run the project.
The game runs without Node.js, a browser, npm or add-ons.

**Full feature parity is the staged acceptance target; the port is incomplete.**
The playable native project includes all 32 characters' source definitions and
90 terrain/road resources for the 18 qualified maps and five team sizes.
Buildings, live map services and the remaining gameplay systems are pending.
See [MIGRATION.md](MIGRATION.md) for the exact implementation boundaries.

Three oversized source world captures use Git LFS. Install Git LFS before
cloning, or run `git lfs pull` in an existing checkout before rebuilding worlds
or running world-reference tests.

## Play

Choose a battlefield, team size (1–5), faction and pilot. Offline matches fill
remaining seats with bots. For LAN, create a room and let the other player join
your IP on UDP port 8620, then start the match. All peers need this Godot project;
the browser game's websocket protocol is different.

WASD moves, mouse looks, left mouse fires, right mouse zooms, 1/2 changes weapon,
Space jumps/ascends, C descends, Shift sprints, R reloads, Q/E requests abilities,
B opens the supply shop, M expands the map, and Escape opens the battle menu.
Basic controller movement/look and action buttons use Godot's InputMap.

Only explicitly implemented abilities are available. The UI reports an
unavailable ability instead of inventing substitute behavior.

Laser-guided launchers freeze the firing-time aim point. Fire-and-forget missiles
acquire the firing-time exact-ray target or an eligible hero in the source aim
cone, retaining a valid confirmed anchor; without a target they fly under
gravity. These warheads now travel and collide on the authority before dealing
blast damage.

Launch range uses the original target-dependent altitude frame. Confirmed
locks appear in the pilot's private HUD, refresh at the source quarter-second
interval and can continue for a missile already in flight after aim release.
Direct/blast target advice now reports geometric reachability and warns inside
the source arming/minimum-range distance. It uses the native eye origin and
source spawn-time measured model centres. Source weapon-footprint rosters now
highlight the predicted direct, blast, fan and penetration victims. Shared
glow resources warn the whole shot, clear in the shop and disappear with hidden
targets. Exact source muzzle placement and animated visual-mesh queries remain
pending.

All 32 pilots now have source-built native first-person cockpit geometry.
Weapon roots follow source reload, recoil-kick and lob elevation limits;
aiming hides cockpit parts until the camera returns to its normal FOV. Morph
pilots select the matching ground/air weapon group. Animated weapon mirrors,
barrel progression, payload omission and muzzle flashes now follow source
events and clips. Full morph transitions, burst echoes, authority muzzle origins
and final toon appearance are pending.

Unguided launchers now solve a 45-degree ground throw or a crosshair-selected
AA trajectory, lowering charge only when the low arc is blocked. A native dashed
arc shows the authority's launch solution. Firing below the minimum safe range
can damage the shooter and allies.

Ordinary gun rounds now fly under source gravity and stop at the first observed
enemy. Penetrating gun rounds pass through bodies and settle their planar line
damage once the trajectory hits scenery or reaches its range boundary. Beam and
rail attacks retain the source's instant behavior.

Base guns now launch two independent incoming missiles. They lose guidance when
the target escapes the launch envelope; intercepted missiles disappear without
blast damage and award the source bounty. Instant beams, kinetic shots and
penetrating lines can intercept them. Player FNF/lob warheads remain a separate
projectile family.

## Dedicated server

```powershell
godot --headless --path . -- --server --port 8620 --team-size 1
godot --headless --path . -- --server --websocket --port 8620 --team-size 1
```

ENet uses UDP. WebSocket uses TCP and accepts `ws://host:8620` in the join field.
For Internet hosting, run the same headless server on the hosting machine and
expose the selected transport. A TLS reverse proxy can terminate WSS upstream.
The dedicated lobby starts two seconds after the first player registers; empty
seats become bots. Late joins are rejected; a disconnected pilot becomes a bot.

## Validation

```powershell
godot --headless --path . res://tests/run.tscn
godot --headless --path . res://tests/worlds.tscn
godot --headless --path . -- --smoke
./tools/test_network.ps1 -Godot C:/path/to/godot_console.exe
./tools/test_network.ps1 -Godot C:/path/to/godot_console.exe -LobControl
./tools/test_network.ps1 -Godot C:/path/to/godot_console.exe -KineticShots
./tools/test_network.ps1 -Godot C:/path/to/godot_console.exe -MissileShots
./tools/test_network.ps1 -Godot C:/path/to/godot_console.exe -Reachability
./tools/test_network.ps1 -Godot C:/path/to/godot_console.exe -Footprints
./tools/test_network.ps1 -Godot C:/path/to/godot_console.exe -Cockpits
godot --headless --path . res://tests/lob_preview.tscn
godot --headless --path . res://tests/reachability.tscn
godot --headless --path . res://tests/models.tscn
godot --headless --path . res://tests/footprints.tscn
godot --headless --path . res://tests/cockpits.tscn
```

The test scene compares GDScript against fixtures evaluated by the original
JavaScript seams, and exercises authority, purchases, ammo, reload deadlines,
respawn and outcome settlement. Network checks use separate server/client
processes for both transports; `-LobControl` also checks private fire-control
snapshots and physical shot segments. `-KineticShots` verifies light-round flight
and heavy-round termination events. `-MissileShots` checks base launches, missile
geometry/HP snapshots, fire commands, interception events and bounty replication.
`-Reachability` checks private target advice, clear/warning HUD transitions and
hidden-target removal. `tests/reachability_preview.tscn -- --capture-preview`
writes a rendered aiming HUD to `tests/reachability-preview.png` with a graphical
display. Reachability fixtures run the original source advisory/arc seams across
all pilot weapon tiers, including obstruction and warning boundaries.
Model-centre fixtures execute the source model builders and spawn measurement
block, including both mercenary factions and combined morph geometry. Native
acquisition checks include a cone-edge case that the former body midpoint misses.
Footprint fixtures evaluate the original client victim roster for every weapon
tier, including its separate 3D penetration basis and reused blast aim buffer.
`-Footprints` verifies a two-victim private roster, warning/normal glows, shop
clearing and hidden-target removal over both transports.
`tests/footprint_preview.tscn -- --capture-preview` writes two rendered glows to
`tests/footprint-preview.png` with a graphical display.
Cockpit fixtures compare all 32 original source graphs, indexed rest ports,
reload/kick/lob poses and aim/FOV/morph visibility. Another 1,456 original full
animation frames compare receiver/payload/finger mirrors, barrel progression,
duplicate events and shared fallback-cache aliases; source clip tracks use native
Animation resources. Flash fixtures cover lifetime, heavy size and aiming.
`-Cockpits` verifies authority serial/clock feedback, sequence/flash presentation,
reload presentation, private elevation and zoom/death hiding over both
transports. `tests/cockpit_preview.tscn -- --character m01 --capture-preview`
writes the native first-person view to `tests/cockpit-m01.png` with a graphical
display. These checks do not certify dynamic muzzle origins or final shaders.
Add `--fire-feedback --feedback-slot heavy` to capture an accepted-shot flash in
`tests/cockpit-m01-fire.png` instead of the resting view.
Structural fixtures compare source blast layers and support-height references,
including bridge overflow, tunnel portals, gallery exits and all 90 accepted
world profiles. Native impact checks cover player warheads and SAM fuses.
`tests/missile_preview.tscn` writes a rendered missile to
`tests/missile-preview.png` with a graphical display.
`tests/lob_preview.tscn -- --capture-preview`
writes a rendered lob HUD/arc to `tests/lob-preview.png` with a graphical display.
World checks compare source mesh topology,
ray heights, layered bridge surfaces, tunnel portals and native player support
under source gravity at the configured physics rate. `--capture` writes a rendered battle view to
`tests/battle.png`; this command requires a graphical display.

## Update imported content

```powershell
node tools/import_source.mjs ../steel_vs_swarm
godot --headless --path . res://tools/import_cockpits.tscn
node tools/bake_worlds.mjs --reuse
node tools/world_references.mjs
godot --headless --path . res://tools/import_worlds.tscn
```

This optional developer command evaluates the original balance/venue seams,
exports resolved values, copies existing glTF/audio/content resources, and
records SHA-256 provenance. It requires the source checkout and its development
Playwright/Chromium runtime for offline model measurement; ordinary play does
not. `PW_CHROME` can select an installed Chromium executable. Imported maps
include only presets admitted by the source's qualification
checks, with the source's active lane subsets and solved tower positions.
The source importer also exports the original cockpit builders' geometry,
textures and pose/visibility fixtures. The native cockpit importer packs those
graphs into `assets/cockpits/*.scn`; `data/cockpits/` is development-only and is
excluded from exports. Runtime cockpit presentation loads only native scenes
and imported scalar metadata.

World baking additionally uses the original development Playwright runtime,
cached Three.js modules and validated OSM/elevation captures. `SVS_SOURCE` can
select a different source checkout. Optional map IDs limit both world tools
(for example `berlin madrid`); pass them after `--` to Godot's importer/tests.
The baker runs the original terrain and road-generation seams offline, resamples
verified raw elevation tiles into the current battlefield frame, and rejects
incomplete coverage. Missing elevation coverage is captured into this project's
`data/source_elevation/`. Geographic imagery requests are omitted.

Source modules, generator, map configuration, captures and tile hashes control
cache reuse. The native importer packs geometry and collision into compressed
Godot resources. Development JSON bundles and raw tiles are excluded from
exports. Runtime requires neither the source checkout nor the bake tools.

## Architecture

| Responsibility | Native implementation |
| --- | --- |
| Room lifecycle and transports | `Session`, `OfflineMultiplayerPeer`, `ENetMultiplayerPeer`, `WebSocketMultiplayerPeer`, RPC |
| Gameplay settlement | `BattleSimulation`, authority-only commands and snapshots |
| Collision and movement | Built-in Jolt, `CharacterBody3D`, `StaticBody3D`, native ray queries |
| Terrain and roads | Source-derived `ArrayMesh`, compressed `Resource`/`PackedScene`, native triangle/convex collision |
| Lane path sampling | `Curve3D`, `Path3D`, `PathFollow3D` |
| Model and animation import | glTF `PackedScene`, `AnimationPlayer` |
| Menu, HUD, shop and input | `Control`, `Container`, `CanvasLayer`, `InputMap` |
| Environment and audio | `WorldEnvironment`, `ProceduralSkyMaterial`, `DirectionalLight3D`, `AudioStreamPlayer` |

Game-specific math remains custom where the engine has no equivalent: source
range envelopes, shield budgets, damage falloff, fan bins, penetration zones
and deterministic uint32 replay. Engine primitives handle their supporting
physics, serialization and presentation.

## License

Game code and original assets retain the source's Apache-2.0 license; see
`LICENSE`. Imported audio retains its existing attribution in
`assets/audio/README.md`. Godot itself is distributed under the MIT license and
is not bundled with this project.

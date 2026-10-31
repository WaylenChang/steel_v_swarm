# Opus-unblocking fixes — outstanding work

Read [AGENTS.md](AGENTS.md). Select one task; its exclusive files are in the root
lease table. SN1-SN7 can run concurrently. SN8 waits for Opus O25/O26 and SN7.
SN9 runs last. Each task records only its current failure.

Local tools: process-local `SVS_SOURCE=C:/Users/user/Documents/app/steel_vs_swarm`,
`PW_CHROME=C:/Users/user/AppData/Local/ms-playwright/chromium-1234/chrome-win64/chrome.exe`
and Godot at
`C:/Users/user/AppData/Local/Temp/steel-v-swarm-godot/Godot_v4.7.2-stable_win64_console.exe`.

Isolate one suite with
`godot --headless --path . res://tests/run.tscn -- --fixture-suite=tests/<suite>.gd`.

## Presentation and lifecycle

- [ ] **SN1 — MultiMesh copies:** add one helper in `scripts/multimesh_copy.gd`
  and use it for the `MultiMesh.duplicate()` calls in the scenery, climb, aquatic,
  wildlife and petal presentations and `scripts/view_occlusion.gd`. Allocate a
  fresh `MultiMesh`, then copy `transform_format`, `use_colors`, `use_custom_data`,
  `mesh`, `instance_count`, `visible_instance_count`, `custom_aabb` and `buffer` in
  that order: Godot 4.7.2 `duplicate()` calls `set_buffer` before `instance_count`.
  Preserve source instance transforms and duplicate before camp clearance. Also
  match `expandByObject` descendant bounds, nine TPS body samples and instanced fade
  restoration. Acceptance: `tests/structure_suite.gd` rotated, mirrored, zero-scale,
  overlap and repeated-clearance cases, `tests/view_occlusion_suite.gd`, and the
  scenery, climb-arrow, aquatic, wildlife and petal `_retirement.tscn` scenes.
- [ ] **SN2 — Preferences and field fog:** `scripts/control_preferences.gd` checks
  `has_section_key("presentation", "low_power")` before `ConfigFile.get_value` with
  a `null` default and keeps `lookSens` clamp/persistence in `tests/mobile_suite.gd`.
  `scripts/audio_preferences.gd` validates bracketed INI section headers before
  `ConfigFile.parse` for `tests/audio_suite.gd` and matches
  `tests/audio_clip_suite.gd` PCM conversion. Fix the fog vertex failures isolated
  in `scripts/skill_field_presentation.gd`; retain every authority assertion.
  Acceptance: those suites plus `tests/fog_geometry.tscn` and
  `tests/fog_retirement.tscn`.
- [ ] **SN6 — Cast effects:** add the original consumer to
  `scripts/combat_effects.gd` for the public `character`, `side`, `slot`, `fx`,
  `point`, `radius`, `duration`, `level`, `fraction`, `carrier`, `origin` and
  `cast_duration` reports. Match `public/js/game.js` and `castfx.js`: a hidden or
  removed caster anchors at the effect point, and carrier casts defer their
  destination effect until delivery. Never infer a generic effect from a passing
  publication fixture. Acceptance: a source-based native fixture for both branches,
  with `tests/cast_events_suite.gd` unchanged.

## Test fixtures

- [ ] **SN3 — Network clocks:** the body, burst, camera, cockpit, death, footprint,
  mobile, projectile-visual, TPS and view `tests/*_network.gd` clocks start at scene
  start; authored world loading outlasts their 15-18 s limits. Count from
  `Session.launch_announced` as `tests/blast_network.gd` does. In
  `tests/death_network.gd`, compare and send through `Session.seats.player_for` and
  `transport_for`, because `peer_id` is a seat and `rpc_id` takes a transport.
  Acceptance: each script parses and passes its transport case in SN9.
- [ ] **SN4 — Model suites:** `tests/body_suite.gd` and
  `tests/civilian_body_suite.gd` consume cases incrementally through
  `Content.read_fixture_part(key, index)`, retaining every row, nested frame
  sequence, rig reset and cross-frame state. Do not raise the encoded-byte budget.
  `tests/burst_suite.gd` parents cockpit fixture units under a `BattleSimulation`
  before `CockpitRig.update_view`, retaining all frames and serial/kick/muzzle
  assertions. `scripts/civilian_body_builder.gd` unsets `owner` before reparenting
  template nodes in `configure`. Acceptance: all three suites with bounded memory,
  and `tests/snapshot_suite.gd` without inconsistent-owner warnings.
- [ ] **SN7 — Shared fixture corrections:** `tools/fixture_json.mjs::writeSourceFile`
  gives each invocation a unique temporary identity and removes only files it
  opened; fixed-clock concurrent writes must not delete a sibling's staging file.
  `tests/aquatic_render.gd`, `tests/death_render.gd`, `tests/minimap_fog_render.gd`
  and `tests/splat_render.gd` pass explicit section arrays to
  `Content.read_json("res://data/fixtures.json", ...)`; record the resulting consumer
  refresh for O25. `tests/campaign_suite.gd::dialogue_lifecycle` advances a
  controlled wall clock: an early signal must not advance the line and the deadline
  advances it once. `tests/death_sequence_suite.gd::run` breaks its lambda cycle
  without weakening `_lifecycle`. `tests/raster_compare.gd` compares exact bytes,
  keeping premultiplied semantics. Acceptance: the full text of each request
  (search "Opus — source publisher temporary ownership", "shared campaign dialogue
  deadline fixture", "shared death integration fixture cleanup" and "raster
  comparator byte boundary" in the Sol and Terra backlogs).

## Generated content

- [ ] **SN5 — Companion scenes:** `assets/companions/guer_tank.scn` nodes 61/62 and
  `assets/companions/{steel,swarm,super}_main_battle_tank.scn` nodes 81/82 must match
  the captured `companionGeometry` world bounds and hierarchy within the existing
  tolerance. Change `tools/import_cockpits.gd`, then regenerate with
  `godot --path . res://tools/import_cockpits.tscn -- --companions` on a real driver.
  Acceptance: `tests/companion_suite.gd` with complete spawn, height and lifecycle
  scope. Run alone.
- [ ] **SN8 — Baseline authored world:** blocked by O25, O26 and SN7. After their
  contracts are accepted, bind them in `tools/source_world_meshes.gd` and
  `tools/import_worlds.gd`, then regenerate the bundles selected by smoke and the
  baseline transports through `tools/migrate_worlds.ps1`. All `berlin_1_*` captures
  lack `deckProbes`, so `tools/import_worlds.tscn` rejects them until the corrected
  `tools/world_references.mjs` reruns; the three existing `berlin_1_*` native
  resources are unqualified. `scripts/room_world_resources.gd`, `scripts/world.gd` and
  the generated seasonal resources must agree, with no early simulation or
  fabricated map. The complete manifest stays in Sol S1. Acceptance:
  `tests/worlds.tscn -- --bundle=<bundle>`, `SMOKE_PASS` and both baseline
  transport cases. Run alone.

## Integrated reruns

- [ ] **SN9 — Rerun and report:** after SN3 and SN8, run the changed clocks, then
  the root suite, smoke and affected transports, one switch per run. Record each
  failure as an exact Opus request; do not fix authority or lifecycle code.
  - `-Bots` on both transports: `tests/bot_network.gd` now starts mid-lane with the
    target 30 m down the push direction. If it times out, check terrain/building LOS.
  - `-Rooms` on both transports: read `recoveries` in the client failure line. If it
    is zero, the second `_begin` has another source.
  - Aiming, campaign, controls, missile, reachability, room and SUPER clocks have
    not been run since their guard landed.
  - `-Campaign` reported `Unavailable` at `scripts/main.gd:246` in sequential runs;
    check port release before reading it as a mode timeout.

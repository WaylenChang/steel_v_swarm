# Migration router

Full feature parity requires outstanding implementation and integrated acceptance.
This file is a stable index; mutable work belongs in exactly one backlog below.
Imported definitions, packed scenes and passing component fixtures do not certify
a complete match, seasonal world set, transport lifecycle or platform delivery.

## Select one workstream

| Tier | Scope | Instructions | Outstanding work |
| --- | --- | --- | --- |
| 1 — Gemini Flash | Bounded UI, settings panels and authored HUD composition | [AGENTS](migration/flash/AGENTS.md) | [Backlog](migration/flash/MIGRATION.md) |
| 2 — ChatGPT Sol 6.1 | World/resource pipelines, audio, input and combat presentation integration | [AGENTS](migration/sol/AGENTS.md) | [Backlog](migration/sol/MIGRATION.md) |
| 2 — ChatGPT Terra 6.1 | View/scope, minimap, PiP and campaign presentation with explicit fixtures | [AGENTS](migration/terra/AGENTS.md) | [Backlog](migration/terra/MIGRATION.md) |
| 3 — Claude Opus | Authority, shared lifecycle, difficult source semantics and final acceptance | [AGENTS](migration/opus/AGENTS.md) | [Backlog](migration/opus/MIGRATION.md) |
| Separate — Models | Mechs, gameplay NPCs, combat buildings, rigs and model damage | [AGENTS](migration/models/AGENTS.md) | [Backlog](migration/models/MIGRATION.md) |

These are task-routing defaults, not a universal intelligence ranking. Model
selection evidence and caching caveats are optional reading in
[MODEL_ROUTING.md](migration/MODEL_ROUTING.md). Routine work does not load it.

## Exclusive file ownership

Documentation directories are disjoint. Runtime files stay in their existing
locations; the following first-match rules give each file exactly one owner.
Ownership follows responsibility, regardless of which model executes the task.
A harder task may use a stronger model within the same workstream without moving
its files or loading the stronger model's other workstream instructions.

1. **Opus owns shared integration surfaces:** `scripts/main.gd`,
   `scripts/simulation.gd`, `scripts/session.gd`, `scripts/unit.gd`,
   `scripts/content.gd`, `scenes/main.tscn`, `project.godot`, export presets,
   `.github/`, `tests/run.gd`, `tests/run.tscn`, `tests/validation.json`,
   `tools/import_source.mjs`, `tools/test_network.ps1` and
   `tools/export_web.ps1`. Shared fixture/manifest publication is serialized here.
2. **Models owns actor geometry and posing:** `scripts/body_*.gd`,
   `scripts/cockpit_*.gd`, `scripts/authority_body_pose.gd`,
   `scripts/authority_weapon_pose.gd`, `scripts/source_quaternion.gd`,
   `scripts/source_euler.gd`, `scripts/gait_curves.gd`,
   `scripts/geometry_lod_state.gd`, `scripts/weapon_presentation.gd`,
   `scripts/carrier_body_motion.gd`, `scripts/civilian_body_builder.gd`,
   `scripts/missile_body.gd`, `scripts/missile_view_ray.gd`,
   `scripts/view_occlusion.gd`, `scripts/head_mark*.gd`, `scripts/vital_bar.gd`,
   `scripts/first_person_shield.gd`, `scripts/shield_presentation.gd`,
   `scripts/scene_damage_geometry.gd`, `scripts/mobile_damage_geometry.gd`,
   `scripts/damage_fx*.gd`, `scripts/retired_body.gd`,
   `scripts/dissolve_binding.gd`, and `tools/import_cockpits.gd`/`.tscn`.
   Native actor/model scene outputs belong here; imported source/glTF stays
   read-only. Decorative world scenery belongs to Sol.
3. **Flash owns the bounded UI allowlist:** `scripts/native_ui.gd`,
   `scripts/*_settings.gd`, `scripts/room_player_editor.gd`,
   `scripts/room_bot_editor.gd`, `scripts/campaign_ui.gd`,
   `scripts/boss_hud.gd`, `scripts/battle_feed.gd`,
   `scripts/combat_feed_state.gd`, `scripts/status_icon*.gd` and
   `scripts/touch_controls.gd`. Event/command contracts stay with their producers.
4. **Opus owns authority and difficult shared semantics:** remaining
   `scripts/*_rules.gd` except `audio_rules.gd`/`audio_scene_rules.gd`,
   `scripts/*_math.gd`, `scripts/room_*.gd` except
   `room_world_resources.gd`/`room_world_prebuild.gd`,
   `scripts/actor_snapshot.gd`, `scripts/match_recipe.gd`,
   `scripts/fatal_watchdog.gd`, `scripts/bot_brain.gd`,
   `scripts/projectile_motion.gd`, `scripts/missile_motion.gd`,
   `scripts/lob_fire_control.gd`, `scripts/recoil_state.gd`,
   `scripts/shot_history.gd`, `scripts/hurt_bearing_log.gd`,
   `scripts/blast_feedback.gd`, `scripts/ability_charge_state.gd`,
   `scripts/source_*.gd`, `scripts/structure_layers.gd`,
   `scripts/lane_surface_profile.gd`, `scripts/climb_index.gd`,
   `scripts/climb_state.gd`, `scripts/balance_*.gd`,
   `scripts/campaign_progress.gd`, `scripts/audio_music_envelope.gd`,
   `scripts/outline_rules.gd`, `shaders/`,
   `tools/audio_music_gain_capture.mjs` and `tools/outline_*.mjs`,
   `tools/cel_*.mjs`, `tools/texture_*.mjs`.
5. **Terra owns the bounded visual-consumer allowlist:**
   `scripts/camera_pose.gd`, `scripts/player_view_state.gd`,
   `scripts/view_lock_state.gd`, `scripts/scope_*.gd`,
   `scripts/spectator_*.gd`, `scripts/lock_glow_presentation.gd`,
   `scripts/minimap*.gd`, `scripts/pip_*.gd`, `scripts/campaign_*.gd` and
   `scripts/dialogue_*.gd`. Earlier rules retain `campaign_ui.gd`,
   `campaign_rules.gd` and `campaign_progress.gd` with Flash/Opus.
   Dedicated captures/importers for these consumers follow Terra, including
   `tools/import_campaign_hold.gd`/`.tscn` and
   `tools/import_dialogue_fonts.gd`/`.tscn`; shared importers remain Opus-owned.
6. **Sol owns other presentation scripts** under `scripts/`, plus native
   world/audio importers, world capture/storage/selection tools,
   `tools/migrate_worlds.ps1` and `tools/import_audio_source.mjs`.
7. A dedicated test scene, fixture adapter or reference generator follows the
   owner of its production target. A file covering multiple owners, an unmatched
   tool, or a shared generated registry belongs to Opus. Shared graphics helpers
   remain Opus-owned even when consumed by Models, Sol or Terra.

Do not edit another owner's file to finish a local task. Add an exact handoff to
your own backlog, naming the producer/consumer contract and the acceptance case.
The target owner pulls that request only when integrating that contract. New
ownership exceptions must be settled before concurrent edits begin; ordinary
progress never rewrites this router. Concurrent runs of publishers that overwrite
the same generated output are also prohibited, even if their source edits differ.

## Sol/Terra concurrency contract

- S12-S14 and S20 belong to Terra; S1-S11, S15-S19 and S21 remain Sol.
  Existing task IDs stay stable. Difficulty changes the execution model, never
  file ownership: a complex Terra task can use Sol under Terra instructions.
- Consumers use existing producer APIs read-only. Freeze payload shape, clock,
  lifecycle and resource ownership before separate changes; an API change is a
  handoff naming the target file, contract and acceptance case. The producer's
  owner implements it separately. Neither lane edits the other's backlog.
- Dedicated tests, fixture captures and generated resources follow their single
  production target, including `.uid` companions. Mixed-owner files, shared
  registries and publication helpers stay with Opus. Imported originals remain
  read-only. New files require an unambiguous owner before concurrent edits.
- Use `artifacts/sol/`, `build/sol-*` and `artifacts/terra/`, `build/terra-*`
  for new lane-local diagnostics, preferences and caches. Existing evidence
  paths remain valid and read-only to the other lane. Use distinct output
  arguments for captures/tests that support them; fixed-output generators,
  shared `.godot` imports and publishers must run serially. Independent code
  editing does not authorize concurrent writes to common generated outputs.

## Completion policy

Each backlog contains only unresolved work and constraints required to finish it.
Delete completed items with no remaining dependency; do not add dated checkpoints,
completed checklists, superseded failures, copied logs or migration history.
Keep live blockers and unsupported behavior explicit. Evidence may be inspected
from its existing test/artifact location without copying it into shared prompts.

No historical partial test result certifies the current build. Runtime acceptance
uses `tests/run.tscn`, the runtime smoke test and relevant ENet/WebSocket cases;
world/model/render/export checks are added by the selected task. Missing content
or an unrun check remains an open item, never a passing result.

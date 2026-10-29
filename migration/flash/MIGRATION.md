# Bounded UI and settings — outstanding work

Read [AGENTS.md](AGENTS.md), then only the selected task's evidence below.
File ownership follows the root router; assigning Gemini Flash does not transfer
producer, authority, shader or shared-fixture ownership.

## Ready for bounded implementation

- [ ] **F1 — Touch reset mirror reentry:** own only
  `scripts/touch_controls.gd` and new dedicated
  `tests/flash_touch_reset.gd`/`.tscn` plus their `.uid` companions.
  Seal the old `held` mirror before `TouchState.reset()` emits synchronous
  releases; the current trailing clear erases a newly admitted hold's mirror.
  Read `scripts/touch_state.gd`, `tests/fixtures/touch_reset.json` and
  `tests/touch_reset.gd` without editing them. Existing reproduction:
  `artifacts/sol/touch-mirror-probe.log` retains state pointer 8 as fire while
  the control mirror is empty. Acceptance: fresh fire/jump holds, same-pointer-ID
  replacement and nested resets retain both state and mirrored commands; old
  holds release once in source order. Check focus/overlay reset and control-node
  retirement with a real scene. Source-state probes alone do not certify the
  control wrapper, hardware pointer capture or populated mobile delivery.

- [ ] **F2 — Chapter replay return label:** own only
  `scripts/campaign_ui.gd` and new dedicated
  `tests/flash_campaign_replay.gd`/`.tscn` plus their `.uid` companions.
  `_play_intro(false)` currently passes the shared arrowless briefing label.
  Read `CampaignCinematic.play()` and its existing empty-override selection,
  `data/campaign_ending.json` and `tests/fixtures/campaign_ending.json`.
  Reuse that source-derived chapter default rather than changing `data/ui.json`,
  a producer or imported data. Acceptance: chapter replay displays the captured
  chapter return label and returns to briefing; deployment, the separate briefing
  button and the prologue terminal retain their own labels and behavior. Exercise
  the CampaignUi caller, not only the cinematic's already-covered label selector.

## Existing implementation awaiting verification

- [ ] **F3 — Authored settings panel acceptance:** native visual, control and
  audio panels already exist; current implementation is not a passing result.
  Own new test-only `tests/flash_settings_acceptance.gd`/`.tscn` and companions;
  keep production files read-only during this task. Inspect the existing
  `tests/test_flash_bounded_ui.gd`/`.tscn` as a diagnostic entry point. Its
  assertions mostly cover node construction; it also calls authority-backed
  combat-feed tests, so do not treat it as isolated UI or rewrite mixed-owner
  coverage here. Reuse original metadata from `Content.balance`,
  `tests/fixtures/visual_preferences.json` and only the selected
  `mobilePreferences`/`mobileTouchPreferences`/`audioPreferences` fixture sections
  through existing loaders, all read-only. Choose actual declared presets
  rather than hardcoded IDs. Verify actual GUI selection/reset, source labels/ranges,
  repeated programmatic sync without feedback writes, restored settings and
  panel release/recreation in portrait/landscape with wrapping and safe insets.
  Read only the selected panel and its preference API; local UI failures become
  separate bounded Flash fixes, producer/authority failures become exact handoffs.
  Do not claim world-text rendering, dynamic resolution, audible output, hardware
  gyro or room authorization from settings-panel success.

## Blocked on accepted producer contracts

- [ ] **F4 — Settlement transcript host:** own `scripts/campaign_ui.gd::show_result`
  and dedicated `tests/flash_settlement_host.gd`/`.tscn` plus companions after
  dependencies are accepted. Preserve source host width, outer overflow,
  title/statistics/buttons and the inner script's 42vh cap; background portraits
  must not enter text flow. Read `scripts/campaign_dialogue.gd` and
  `tests/fixtures/dialogue_layout.json` only for this task. The capture populates
  only `overTalk`, so it cannot certify complete winner/statistics/host layout.
  Before implementation, require accepted Opus font advances and portrait/frame
  materials, Terra's matching inner-dialogue binding, and a dedicated original
  populated settlement capture. A host-only capture follows Flash; shared capture
  helpers/publication remain Opus-owned. Acceptance: populated victory/defeat and
  replay at 360/720/721/1440 px widths, including nested nearest scrolling and
  repeated replay/cleanup. Do not patch inner dialogue, fonts or shaders locally.

## Scheduling and acceptance boundaries

- F1, F2 and F3 have disjoint write sets and may run in separate chats/worktrees
  with stable read-only producer APIs. F2 and F4 share `campaign_ui.gd` and must
  run serially. One writer updates this backlog; completed tasks are removed.
- Use process-local `APPDATA=build/flash-user` and
  `LOCALAPPDATA=build/flash-local`; task-specific reports belong under
  `artifacts/flash/`. Separate concurrent verification output/preferences per
  task. Fixed-output captures, shared imports and publication remain serialized.
- Runtime edits require the dedicated scene, `tests/run.tscn`, runtime smoke and
  both transports with relevant `-Mobile`/`-Controls` or `-Campaign` cases, one
  switch per run. Only Opus changes shared registration/consumer plans. Missing
  authored worlds, source identity failures or unrun checks remain explicit
  blockers; component passes never establish full-match acceptance.

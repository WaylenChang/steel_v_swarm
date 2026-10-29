# Bounded UI and settings — outstanding work

Read [AGENTS.md](AGENTS.md), then only the selected task's evidence below.
File ownership follows the root router; assigning Gemini Flash does not transfer
producer, authority, shader or shared-fixture ownership.

## Ready for bounded implementation

None.

## Existing implementation awaiting verification

None.

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

- F2 and F4 share `campaign_ui.gd` and must run serially. One writer updates
  this backlog; completed tasks are removed.
- Use process-local `APPDATA=build/flash-user` and
  `LOCALAPPDATA=build/flash-local`; task-specific reports belong under
  `artifacts/flash/`. Separate concurrent verification output/preferences per
  task. Fixed-output captures, shared imports and publication remain serialized.
- Runtime edits require the dedicated scene, `tests/run.tscn`, runtime smoke and
  both transports with relevant `-Mobile`/`-Controls` or `-Campaign` cases, one
  switch per run. Only Opus changes shared registration/consumer plans. Missing
  authored worlds, source identity failures or unrun checks remain explicit
  blockers; component passes never establish full-match acceptance.

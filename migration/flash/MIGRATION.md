# Bounded UI and settings — outstanding work

Use [AGENTS.md](AGENTS.md) before implementation. Items below require acceptance
on the current imported content; existing UI code is not a passing result.

## Settings and room panels

- [ ] **F3 — Loading/failure UI:** certify source preload captions, completion,
  automatic retry and first-failure dialog text. Resource fractions must not be
  displayed as whole-scene percentages. The shared loading/fatal handler is an
  Opus integration surface; resource/prebuild state is supplied by Sol.
- [ ] **F4 — Deployment presentation:** finish supported preference/favorite
  controls and original loading artwork/progress/error presentation only where
  their source contracts and content are available. Keep unsupported map recipes,
  directory/PIN actions and missing campaign/SUPER content unavailable.

## Acceptance and handoffs

Keep unfinished integration requests here with target file, required input/output
and a failing acceptance case. Delete each item once its relevant component and
integration checks pass and no dependency remains; keep no completion ledger.

### Handoffs to Opus / Sol

- **Target:** `scripts/main.gd` (Opus)
  **Input:** Integration of `VisualSettings` panel into the main settings menu.
  **Contract:** Add `VisualSettings.new()` and `settings.configure(Visuals)` into the settings column alongside `ControlSettings`, `BalanceSettings`, and `AudioSettings`.
  **Acceptance:** Visual preset selection and world language switches are accessible from the main settings menu.

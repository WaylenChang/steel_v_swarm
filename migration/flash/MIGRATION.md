# Bounded UI and settings — outstanding work

Use [AGENTS.md](AGENTS.md) before implementation. Items below require acceptance
on the current imported content; existing UI code is not a passing result.

## Acceptance and handoffs

Keep unfinished integration requests here with target file, required input/output
and a failing acceptance case. Delete each item once its relevant component and
integration checks pass and no dependency remains; keep no completion ledger.

### Handoffs to Opus / Sol

- **Target:** `scripts/main.gd` (Opus)
  **Input:** Integration of `VisualSettings` panel into the main settings menu.
  **Contract:** Add `VisualSettings.new()` and `settings.configure(Visuals)` into the settings column alongside `ControlSettings`, `BalanceSettings`, and `AudioSettings`.
  **Acceptance:** Visual preset selection and world language switches are accessible from the main settings menu.

- **Target:** `assets/loading/` (Sol)
  **Input:** Import source loading artwork.
  **Contract:** Publish native Texture2D resources for loading backgrounds (`steel_vs_swarm_1..6`, `steel_vs_mercenary_1..6`, `swarm_vs_mercenary_1..6`) under `assets/loading/`.
  **Acceptance:** Loading textures are loadable by participant faction combination.

- **Target:** `scripts/main.gd` (Opus)
  **Input:** Loading artwork, map details, and progress presentation during `loading` phase.
  **Contract:** Display place/biome metadata, progress bar reflecting `room_world_prebuild` and `setup_progress`, and random background artwork matching room participant factions when available in `loading_panel`. Keep unsupported custom map recipes and PIN actions unavailable.
  **Acceptance:** Entering `loading` phase presents map details, progress bar, leave button, and background artwork until `Session.launch_announced`.

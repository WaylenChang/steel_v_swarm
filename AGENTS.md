# Steel vs. Swarm — Godot Port

- Runtime code MUST be GDScript. Use Godot 4 native scenes, physics, animation,
  UI, audio, resource imports and MultiplayerAPI before adding custom systems.
- No add-ons, GDExtension, C#, JavaScript runtime, embedded browser or Node server.
  `tools/import_source.mjs` is an offline migration tool, not a runtime dependency.
- HP, damage, ammunition, purchases, respawns and outcomes settle only in
  `scripts/simulation.gd` on the authority, including offline matches.
- Offline, ENet and WebSocket sessions share one simulation and room lifecycle.
- Imported source data and glTF assets are read-only. Regenerate them with the
  import tool; never manually retune derived numbers.
- New gameplay implementations require source-based equivalence fixtures.
  Keep intentional blast coverage, planar penetration, building clamps,
  shield-budget overflow, bot limits and fire-rate budgets.
- Independent scenery randomness must never consume the combat RNG stream.
- Comments and documentation use English. Traditional Chinese UI and narrative
  content belong in `data/`.
- Unsupported mechanics must remain explicitly unavailable until their source
  semantics are implemented. Do not substitute a generic attack or fabricated map.
- Read `MIGRATION.md` before claiming feature parity. Run `tests/run.tscn`, the
  runtime smoke test and transport tests after relevant changes.

# Terra — bounded visual consumers

## Scope and loading

Apply the root first-match ownership rules. Default to ChatGPT Terra 6.1 for
scoped visual fixes with supplied source evidence and explicit acceptance.
Own only the root Terra allowlist and its dedicated tests, captures, importers
and native outputs. Flash retains authored HUD/settings and campaign result
hosting; Sol retains input, combat effects, audio and world/resource pipelines;
Opus retains shared integration, source semantics and shaders; Models retains
actor geometry and occlusion.

Read this file, then [MIGRATION.md](MIGRATION.md), then only the selected task's
consumer, source oracle and acceptance commands. Sibling backlogs and
[model research](../MODEL_ROUTING.md) are opt-in. Commands run from the root.
Nested instructions here must be explicitly selected from a root-started chat.

## Implementation contract

- Prefer Godot Control/Container, Camera3D, SubViewport, ResourceLoader,
  native animation and existing utilities. Check existing helpers before adding one.
- Take one bounded task with named files, source inputs and a verifiable outcome.
  If it needs deeper reasoning, use Sol within this same ownership lane; do not
  acquire Sol-owned files or expand to a broad architectural rewrite.
- Consume producer APIs read-only. Preserve clocks, order, null/zero distinctions,
  double-to-native boundaries, cancellation, private materials and resource release.
  Do not change combat state, authority visibility or shared RNG.
- Keep unsupported source behavior unavailable. Shared shader/numeric/font
  semantics require an exact handoff before consumer implementation. Preserve
  strict failing fixtures and raster tolerances until their contracts are accepted.
- Dedicated scene/fixture/native resource outputs follow their consumer owner.
  Imported source/glTF and existing evidence remain immutable. Shared manifests,
  fixtures, helpers and importer registries retain root ownership.
- New diagnostics use `artifacts/terra/`; preferences/caches use `build/terra-*`.
  Follow the root serialization rule for fixed-output captures, imports and
  publishers. Independent edits never permit two writers to one generated path.

## Acceptance and updates

Use the original source oracle and native lifecycle checks. Real pixels need
real-driver composition, actual imported art/fonts and unchanged raster gates.
Runtime edits require `tests/run.tscn`, runtime smoke and relevant ENet/WebSocket
cases; component success is insufficient. Source tooling also runs its dedicated
Node tests. Documentation-only changes require link/scope checks.

Only this directory's `MIGRATION.md` receives unresolved work, blockers and exact
cross-owner requests naming file, contract and acceptance case. Delete finished
tasks. Keep root routers, all `AGENTS.md`, research and sibling backlogs stable
during routine coding. Put task evidence after stable instructions.

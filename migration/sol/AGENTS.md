# Sol — native presentation and resource pipelines

## Scope

Apply the root ownership rules. This workstream owns the remaining native
presentation scripts and world/audio workflows, excluding model construction,
authority semantics, shared shaders and the unresolved music envelope adapter.
Default to ChatGPT Sol for bounded multi-file integration with source fixtures.

Read this file, then [MIGRATION.md](MIGRATION.md), then the selected module and
its original reference generator. Sibling backlogs and research are opt-in.
Commands run from the repository root.

## Implementation contract

- Prefer Godot resources, native physics queries, audio buses/streams,
  ResourceLoader, SubViewport, Camera3D, particles and existing pool utilities.
- Presentation consumes authority output. It must not spend resources, change
  combat RNG, publish private gameplay state or replace simulation settlement.
- Preserve source order, clocks, nullish/zero distinctions, coordinate frames
  and strict boundary behavior. Do not hide differences with arbitrary epsilons.
- Imported data and glTF are immutable. Regenerate through the existing tool;
  only the owner publishes shared manifests/fixtures. No ad hoc content patching.
- Run large world capture/reference/native-pack steps serially. Validate exact
  bundle identity, dependencies, hashes and completed output before publication.
  Use the existing atomic publication helper; do not truncate a live resource.
- Nonempty MultiMesh packing needs a real renderer; headless dummy-renderer
  success is not valid model generation. Reuse the model owner's packed scenes.
- Missing source resources or unsupported audio/shader shapes reject explicitly.
  Record high-risk semantic or cross-owner changes as exact local handoffs.

## Acceptance

Use source-oracle fixtures plus native resource reload/lifecycle checks. Render
with the real driver for pixels, transparency and resource destruction; inspect
actual mixer output for audio. Require empty engine error output, not assertions
alone. Runtime changes require the root suite, smoke and affected transports.
Source tooling changes also run their existing Node tests. Documentation-only
changes require link/scope checks, not capture, regeneration or game execution.

## Context and updates

Only this directory's `MIGRATION.md` receives mutable work, blockers and handoffs.
Keep `AGENTS.md`, root routing and sibling documents unchanged during routine
work. Append evidence after the stable instructions; delete finished tasks and
superseded diagnoses instead of adding history or cached whole-tree snapshots.

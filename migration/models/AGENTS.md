# Models — mechs, gameplay NPCs and combat buildings

## Scope

This is a separate asset/rig workstream, outside the three model difficulty
tiers. It covers player mechs, gameplay NPCs/civilians/companions/carriers,
missile models and combat towers/bases/camp buildings. Decorative map scenery
stays with Sol; gameplay rules and event production stay with Opus.

Apply the root exclusive ownership rules. Read this file, then
[MIGRATION.md](MIGRATION.md), then only the relevant source builder, packed-scene
adapter and original pose/geometry fixtures. Commands run from the repository
root. Select the execution model for the particular geometry/rig task; file
ownership does not change with the model.

## Modeling contract

- Original source/glTF and derived data are read-only. Change the existing
  offline builder/export/packer path and regenerate; do not hand-retune graphs,
  hit cylinders, muzzles, body scales or animations.
- Use native PackedScene, ArrayMesh, AnimationPlayer, MultiMesh and scene-local
  resources. Preserve hidden nodes, original hierarchy/IDs, material aliases,
  emitter references, logical Euler/quaternion state and signed TRS.
- Preserve source pose composition and immutable event identity. Distinct shots
  at the same clock must advance separately; replaying one event must not.
- Keep visual meshes, authority collision/aim volumes and owner camera rulers
  distinct. Model presentation must not settle damage, move gameplay actors or
  spend resources. Authority-body rigs are read-only pose suppliers to simulation.
- Do not invent rigs for rigless carriers or missing species. Unsupported node/
  material/reference types reject explicitly. Disabled SkeletonHelper identity
  may survive as a placeholder; its visualization remains unavailable.
- Preserve model instance isolation, outline/occlusion/dissolve references,
  source traversal order and restoration on death, reentry and release.
- Real-renderer packing is mandatory for nonempty MultiMesh content. Reuse the
  existing atomic publication helper; coordinate any shared capture/manifest
  publication through Opus. Never publish over another owner's active capture.

## Acceptance

Compare source geometry, all retained pose channels, actual emitters, bounds,
per-instance transforms/colours and material state, including mirrors, shear,
zero scale, morph edges and same-time events. Pack/reload fresh independent
instances with a real renderer and check early-cancel/unrendered release as well
as normal destruction. Engine errors invalidate a clean lifecycle result.
Require relevant source/native suites, populated model/render checks and
offline/ENet/WebSocket acceptance. Root runtime checks apply to code changes;
documentation-only work needs link/scope checks without regeneration.

## Context and updates

Only this directory's `MIGRATION.md` receives progress and exact cross-owner
requests. Shader infrastructure, gameplay events, scene wiring and test/import
registries stay with their owners. Keep instructions/root routing stable; append
task evidence after them. Remove resolved tasks with no remaining dependency and
leave no completed checkpoint/history section.

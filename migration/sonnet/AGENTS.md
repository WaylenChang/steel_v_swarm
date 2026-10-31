# Sonnet — bounded fixes that unblock Opus

## Scope

Apply the root ownership rules. Default to Claude Sonnet 5.5 for tasks with named
files, an explicit contract and a runnable acceptance case. Each `SN` task owns
only the files in its root lease; this workstream never owns authority semantics.

Read this file, then [MIGRATION.md](MIGRATION.md), then only the selected task's
files and fixtures. Search sibling backlogs and research; do not load them whole.
Commands run from the repository root.

## Implementation contract

- Stay inside the task's lease. Consume every other API read-only and make the
  smallest change that satisfies the named acceptance case.
- Presentation and test fixes must not spend resources, settle damage, change
  combat RNG or publish private state. Keep strict tolerances and every assertion.
- Imported data, glTF and generated output change only through their existing
  tools. Shared fixture consumer plans remain with Opus.
- Unsupported source behavior stays explicitly unavailable.

## Escalate to Opus

Stop and record an exact request in this backlog when a fix needs a file outside
the lease, source semantics stay ambiguous, the change reaches settlement, RNG
order, privacy, membership or transport lifecycle, or a strict fixture still fails
after the named correction. Do not retune values to pass.

## Isolation

- Use one session and one worktree per task. Leases are disjoint, so concurrent
  tasks cannot edit the same file. SN5, SN8 and SN9 run alone because they use
  fixed outputs or shared ports.
- A fresh worktree has no `.godot/`, `build/` or ignored seasonal resources. Import
  there for local use only and never commit resulting `project.godot` changes.
- Use process-local `APPDATA=build/sonnet-<task>-user` and
  `LOCALAPPDATA=build/sonnet-<task>-local`. New reports go to `artifacts/sonnet/`.

## Acceptance and updates

Run the task's dedicated checks with empty engine error output. Root gates stay
listed in SN9 until authored worlds allow them to run; an unrun gate is an open
item, never a pass. Documentation-only changes require link/scope checks.

Only this directory's `MIGRATION.md` receives progress and exact requests. Delete
a task when its dedicated checks pass; deletion ends its lease. Keep root routers,
every `AGENTS.md`, research and sibling backlogs unchanged during routine work.

@AGENTS.md

# Claude Code

- This file exists so every Claude Code version gets `AGENTS.md`. Shared rules
  belong there; keep only Claude-specific loading and model notes here.
- Do not import workstream files. Imports load in every session; select and read
  one workstream instead.
- Search sibling backlogs and `migration/MODEL_ROUTING.md`. Read them whole only
  when the task requires it.
- Start Sonnet tasks with
  `claude --model claude-sonnet-5-5 --effort medium -w <task>`. Use `high` for
  longer tasks, not `max`. The full ID matters on versions before v2.1.284.
- Start Opus lanes with `claude --model claude-opus-5-5 -w <lane>`.
- Keep one workstream per session. Parallel work uses separate worktrees and the
  exclusive files in `MIGRATION.md`.

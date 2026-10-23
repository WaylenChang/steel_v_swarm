# Model routing rationale

Optional planning reference. Do not inject this research into routine workstream
prompts. It explains the current routing decision; it is not a status ledger.

## Difficulty and execution model

| Workstream | Reasoning demand | Default | Escalation boundary |
| --- | --- | --- | --- |
| Flash | Small edit surface, explicit source/UI contract, deterministic acceptance | Gemini Flash | Missing producer semantics, new protocol, shared numeric/shader algorithm |
| Sol | Bounded multi-file native integration, retained state/resources, source fixtures | ChatGPT Sol | Cross-owner authority/lifecycle change or unresolved high-risk source semantics |
| Opus | Coupled authority state, privacy/race/order analysis, exact shader/audio semantics | Claude Opus | Resolve from original source and independent evidence; unavailable if semantics remain absent |
| Models | Geometry, actor rigs, transforms, materials and model lifecycle | Choose per task | Use stronger reasoning for pose composition/aliasing; use a source/render workflow for visual fidelity |

This is a project-specific routing inference, not measured intelligence or a
claim that one model always wins. Model families are preserved as requested;
versions mentioned by commenters are evidence labels, not silently pinned task
settings. A stronger model can execute a difficult Sol/Models task under that
workstream's instructions without changing ownership.

OpenAI describes Sol as an everyday model for coding and work requiring judgment
and recommends comparing actual tasks/settings. That supports the middle lane;
it does not establish a cross-vendor ranking.
[Official model selection](https://developers.openai.com/api/docs/guides/model-selection).

## Developer commentary considered

Search window: 2026-10-09 through 2026-10-23, Asia/Taipei. These are firsthand
community experiences with different codebases, harnesses and subscriptions,
not controlled benchmarks or a representative developer survey.

The following date-confirmed sample is from an October 11 discussion. Its post
and comment timestamps were checked in the original
[Reddit JSON](https://www.reddit.com/r/codex/comments/1x2rqfh.json);
the post's `created_utc=1791670831` is October 11 in Taipei.

- The author reports better dependency understanding and less overengineering
  after switching from Codex Sol/Astra to Opus 5.5. This favors reserving coupled
  integration for Opus, without treating the author's completion claims as an
  independently reproduced result.
  [Developer's project report](https://www.reddit.com/r/codex/comments/1x2rqfh/thank_you_for_all_who_suggested_to_try_claude/).
- A commenter defends Sol 6.1's capability and usage efficiency. This is a useful
  counterpoint to the thread's negative selection bias and supports retaining a
  substantial implementation lane for Sol.
  [Sol counterpoint](https://www.reddit.com/r/codex/comments/1x2rqfh/thank_you_for_all_who_suggested_to_try_claude/pf54eii/).
- Another commenter places Sol 6.1 and Gemini 3.8 Flash together below Opus 5.5.
  That contradicts a rigid Flash-versus-Sol intelligence ladder. The repository
  therefore separates their default task risk/context burden and retains the
  same source-fixture acceptance bar for every model.
  [Three-model comparison](https://www.reddit.com/r/codex/comments/1x2rqfh/thank_you_for_all_who_suggested_to_try_claude/pf8dd47/).

Additional retrieved reports describe Flash succeeding on an explicit task and
Flash executing an Opus plan. Their rendered relative timestamps were not
independently resolved, so they are supplementary and excluded from the
date-confirmed sample above. They support bounded-task routing, not a benchmark
or a verified two-week aggregate.
[Flash/Sol task report](https://www.reddit.com/r/google_antigravity/comments/1x6g66p/claude_sonnet_46_thinking_burned_64_of_my/),
[Opus planning/Flash execution discussion](https://www.reddit.com/r/claude/comments/1x22e6n/opus_55_is_insanely_good_compared_to_gemini/).

## Progressive disclosure and cache isolation

Load root `AGENTS.md` and the stable root migration router, then exactly one
workstream's stable `AGENTS.md`, its mutable backlog and task-specific evidence.
Sibling backlogs are never part of the routine prefix. Progress changes only
the selected backlog; completed tasks disappear without a shared changelog.

This is a file/context design, not an API cache implementation. Prefix matching
also depends on provider/model, request boundaries, tool schemas, settings,
cache length and expiry. Caches are not shared between Google, OpenAI and
Anthropic. A local edit cannot guarantee a cache hit in any client.

- OpenAI reuses eligible matching rendered prefixes; changing earlier content
  can invalidate later reuse. Keep stable instruction blocks first and append
  current tasks/evidence. Respect the harness's actual cache boundaries.
  [OpenAI prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching).
- Gemini recommends common content at the beginning and similar prefixes close
  together. Minimum cacheable length and actual cached-token usage still apply.
  [Gemini context caching](https://ai.google.dev/gemini-api/docs/caching).
- Claude caches the prefix through an enabled breakpoint, including tools,
  system and messages. Its API caching configuration and invalidation rules are
  separate from this repository's Markdown layout.
  [Claude prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching).

Codex's initial discovery follows the project-root-to-working-directory chain.
Sibling workstream instructions under `migration/` are therefore explicitly
selected documents when starting at the repository root. Other clients need
their own equivalent loading configuration; there is no assumption that Gemini
or Claude automatically honors every nested `AGENTS.md`.
[Official AGENTS.md discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

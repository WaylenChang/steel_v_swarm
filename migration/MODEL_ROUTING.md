# Model routing rationale

Optional planning reference. Do not inject this research into routine workstream
prompts. It explains the current routing decision; it is not a status ledger.

## Difficulty and execution model

| Workstream | Reasoning demand | Default | Escalation boundary |
| --- | --- | --- | --- |
| Flash | Small edit surface, explicit source/UI contract, deterministic acceptance | Gemini Flash | Missing producer semantics, new protocol, shared numeric/shader algorithm |
| Sol | World/resource pipelines, audio, input and combat presentation integration | ChatGPT Sol 6.1 | Cross-owner authority/lifecycle change or unresolved high-risk source semantics |
| Terra | Fixture-backed view/scope, minimap, PiP and campaign consumer changes | ChatGPT Terra 6.1 | Unresolved source/shader semantics or producer API change; use a stronger model in the same lane |
| Sonnet | Leased fixes with named files, explicit contracts and runnable acceptance | Claude Sonnet 5.5 at `medium` | Use `high` for longer tasks; send ambiguous semantics, authority, privacy or lifecycle changes to Opus |
| Opus | Coupled authority state, privacy/race/order analysis, exact shader/audio semantics | Claude Opus | Resolve from original source and independent evidence; unavailable if semantics remain absent |
| Models | Geometry, actor rigs, transforms, materials and model lifecycle | Choose per task | Use stronger reasoning for pose composition/aliasing; use a source/render workflow for visual fidelity |

This is a project-specific routing inference, not measured intelligence or a
claim that one model always wins. Model families are preserved as requested;
the Sol/Terra defaults explicitly name 6.1. Other versions mentioned by commenters
are evidence labels. A stronger model can execute a difficult Sol/Terra/Models task under that
workstream's instructions without changing ownership.

## Sol/Terra 6.1 evidence and routing decision

Checked on 2026-10-27 (Asia/Taipei). OpenAI's current guidance assigns complex
technical projects to Sol 6.1 and scoped code fixes, visual reasoning and screen
workflows to Terra 6.1. It recommends explicit inputs and verification for Terra
and comparing actual tasks at the same reasoning effort. The GPT-6 guide suggests
starting Terra at medium and measuring whether extra effort is worthwhile.
[Official model selection](https://developers.openai.com/api/docs/guides/model-selection),
[official GPT-6 guide](https://developers.openai.com/api/docs/guides/latest-model).

Early firsthand community reports are mixed, not controlled Godot benchmarks:

- A robotics developer reports using Sol at low/medium successfully, then finding
  Terra high/max less satisfactory and more allowance-intensive on a visual
  construction application. Different efforts and subjective outputs prevent a
  general cost or capability conclusion.
  [Developer comparison](https://www.reddit.com/r/codex/comments/1xgcjjb/gpt_61_terra_on_gpt_plus/).
- A release-thread commenter argues that Terra fits constrained orchestrated
  tasks; this is an opinion rather than a reproduced project result. The thread
  also contains reports of incomplete execution. Its automated thread summary
  is excluded as primary evidence.
  [Firsthand community discussion](https://www.reddit.com/r/codex/comments/1xg4eqq/comment/19rp85thizc03/).

Project inference: retain coupled world/resource, audio, input and combat-effect
integration with Sol. Assign Terra existing view, minimap, PiP and campaign
consumers with explicit source/raster/lifecycle fixtures. Each change stays
bounded; complex camera/cancellation/compositing work can use Sol inside Terra's
ownership lane. Visual scope does not imply easy semantics or a weaker test bar.
Do not infer subscription savings from API token prices or assume high/max Terra
is equivalent to low/medium Sol. Compare completed, accepted work and retries.

Root first-match file ownership, dedicated output ownership and frozen producer
contracts make the two lanes independently editable. Shared registries and
fixed-output publication remain serialized. This is repository routing, not an
OpenAI-endorsed Godot classification or evidence of full game parity.

## Claude Sonnet/Opus evidence and routing decision

Checked on 2026-10-31 (Asia/Taipei). Anthropic assigns complex agentic coding and
large-scale refactoring to Opus 5.5, and everyday coding and agent work to Sonnet
5.5. Sonnet lists at half of Opus's token price.
[Official model selection](https://platform.claude.com/docs/en/about-claude/models/choosing-a-model),
[models overview](https://platform.claude.com/docs/en/about-claude/models/overview).
Its launch page places Sonnet at well-scoped tasks and bug fixing and keeps Opus
ahead on complex, open-ended work. At `max`, Sonnet more often started a
multi-subagent review skill; two examined cases timed out or edited out of scope.
[Sonnet 5.5 launch](https://www.anthropic.com/claude-sonnet-5-5).
The effort guide starts Sonnet at `medium` for well-specified agentic coding,
moves to `high` for harder or longer tasks and reserves `xhigh`/`max` for measured
gains. [Official effort guide](https://platform.claude.com/docs/en/build-with-claude/effort).

Anthropic's multi-model measurements found delegation saved money for routine work
with a long cost tail or work larger than one context window. One dependent chain
did better on one model at lower effort. Its only Sonnet-with-Opus-advisor result,
on a non-coding benchmark, was within noise at 25% more cost.
[Official cost and intelligence guide](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence).
Secondary reporting says Sonnet used more output tokens and cost more per task than
Opus at max effort, and found 6 of 13 known issues against Opus's 8 of 13 in a small
code-review set. [Codersera summary](https://codersera.com/blog/claude-sonnet-5-5-vs-opus-5-5-2026/).

Community evidence is thin and conflicting. Reddit could not be retrieved, so this
sample is Hacker News comments from 2026-10-21 through 2026-10-26, not a survey:

- One developer reports Sonnet as cheaper per task and faster for personal work.
  [Sonnet report](https://news.ycombinator.com/item?id=50243939).
- Another reports Opus as more token-efficient and cheaper per run on a
  reverse-engineering benchmark. [Opus report](https://news.ycombinator.com/item?id=50220395).
- A third reports Sonnet implementation exhausting a team limit about two hours
  into a session. [Usage report](https://news.ycombinator.com/item?id=50178757).

Project inference: price per token alone does not justify Sonnet. Use it where a
narrow contract limits exploration and retries; keep open-ended authority work on
Opus. Run independent leased sessions rather than an Opus orchestrator or advisor.
Compare completed, accepted tasks and retries before widening Sonnet's scope.

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
automatically honors every nested `AGENTS.md`.
[Official AGENTS.md discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

Claude Code reads `AGENTS.md` directly only from v2.1.277, and a root `CLAUDE.md`
takes precedence over it. The installed CLI is 2.1.208, so root `CLAUDE.md` imports
`AGENTS.md`. Imports load in every session, so workstream files stay explicit reads.
[Official Claude memory guide](https://code.claude.com/docs/en/memory).

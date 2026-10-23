# Bounded UI and settings — outstanding work

Use [AGENTS.md](AGENTS.md) before implementation. Items below require acceptance
on the current imported content; existing UI code is not a passing result.

## Settings and room panels

- [ ] **F1 — Settings panels:** certify audio, visual, balance and personal
  control panels against their existing preference APIs. Cover unset/legacy
  values, clamp display, separate SFX/BGM switches, room-forced control modes,
  cancellation and reload. Gameplay tuning, preference normalization and host
  permission checks belong to their producer owners.
- [ ] **F2 — Room editors:** certify faction/mercenary/random pilot choices,
  host-only bot/difficulty controls, ready/cancel display and disconnected marks.
  Character/side reset versus retention must follow authority publication;
  capacity rejection cannot leave optimistic roster state behind.
- [ ] **F3 — Loading/failure UI:** certify source preload captions, completion,
  automatic retry and first-failure dialog text. Resource fractions must not be
  displayed as whole-scene percentages. The shared loading/fatal handler is an
  Opus integration surface; resource/prebuild state is supplied by Sol.
- [ ] **F4 — Deployment presentation:** finish supported preference/favorite
  controls and original loading artwork/progress/error presentation only where
  their source contracts and content are available. Keep unsupported map recipes,
  directory/PIN actions and missing campaign/SUPER content unavailable.

## HUD and authored content

- [ ] **F5 — Status strip:** certify imported SVG glyphs, clock arcs, stack
  badges and responsive placement. Preserve stable time order, duplicate freeze
  entries, positive modifier stacks, per-ID duration maxima, affix separation,
  rounded-zero active buffs and suppression precision. Spectating clears the
  visible strip without clearing retained source duration maxima. Relevant
  references: `tools/status_icon_references.mjs`, `tests/status_icon_suite.gd`.
- [ ] **F6 — Combat feed:** finish missing source reports and certify event
  ordering, identity/replay rejection, private versus public recipients and
  expiry. Include death/collapse, cast-start/completion, purchase/respawn,
  environment, supply/loot/relay/threat and civilian notices. Retain newest-first,
  five-row/six-second source feed limits and imported Traditional Chinese text.
  Authority event production is an Opus handoff, not UI settlement.
- [ ] **F7 — Campaign and BOSS panels:** certify authored chapter/pilot/art
  selection, intro replay, segmented bars, labels, nearest-BOSS display and
  post-victory navigation against existing state. Radio/cinematic clocks,
  progress writes, stage locks and victory eligibility stay producer-owned.
- [ ] **F8 — Shop/HUD presentation:** certify source charge/cooldown mirrors,
  cast/lift displays, weapon advice, civilian G/H prompts and portrait hints.
  Portrait hint lifetime, first admission, resize hiding and pointer dismissal
  must match source behavior. Observer magazines/lift remain unknown; do not
  infer private values. Full HUD typography and rendered placement remain open.

## Mobile layout

- [ ] **F9 — Touch controls:** certify native safe-area placement, independent
  HUD/button mirroring, portrait/landscape resize, cooldown/charge labels and
  shop access while dead. The swap control must retain the current one-body
  source restriction. Pointer ownership, sensor math and gameplay input gates
  belong to Sol/Opus; this item changes their UI consumer only.

## Acceptance and handoffs

Use the existing `status_icon_suite.gd` and `combat_feed_suite.gd` for their
respective contracts, plus source/render checks for the affected panel. Inspect
`tools/test_network.ps1` for the relevant existing room/control/mode case; it
accepts one case switch per invocation and runs both transports.

Keep unfinished integration requests here with target file, required input/output
and a failing acceptance case. Delete each item once its relevant component and
integration checks pass and no dependency remains; keep no completion ledger.

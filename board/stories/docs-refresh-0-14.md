---
kind: docs
status: blocked
blocked_by: [no-herdr-state-for-claude-sessions, sonnet-share]
depends_on: [no-herdr-state-for-claude-sessions, sonnet-share]
touches: [README.md, docs/method.md, docs/dash.md, docs/review.md, docs/assets/swarm-flow.workflow.json, docs/assets/swarm-flow-light.png, docs/assets/swarm-flow-dark.png, docs/assets/board.png]
---

# Docs refresh before v0.14.0: one pass over README, the method, the diagrams and the screenshots

Since v0.13.0 each PR updated its own corner of the docs, but nobody has read them as a whole. The user
asked (2026-10-13) for the README and the other docs to show the new GIF, new diagrams and the rest, with
the humanizer run over everything a person reads. What changed since v0.13.0: agent state read from
`claude agents --json` (wait, status, dash, tell, watch), `require_claude` (2.1.145), the off-screen nudge,
`wait` returning `auth` on an expired login, `tell <slug> <kind> <file>`, `swarm.sh init`,
`swarm.sh outcomes`, the restyled dash, and the `sonnet_share` / `builder_subagent_model` settings.

- **Flow diagram**: update `docs/assets/swarm-flow.workflow.json` so the flow shows `swarm.sh init` before
  `/hld`, and the stops where `/swarm` waits for the user (approval, merge, `lead` story, `auth` → `/login`).
  Re-render the light and dark PNGs with Archify as the README says. If Archify cannot run unattended, stop
  and reply naming the step; the lead or the user renders it.
- **README**: "How it works", "When `/swarm` stops for you" (add the expired-login row), "Cost and
  safety" (the sonnet_share experiment and builder_subagent_model, both off by default) and the command
  table read as one document; the dash GIF's alt text matches the GIF.
- **docs/method.md, docs/dash.md, docs/review.md**: consistent with the code at this PR's base; no section
  describes herdr's status as the state source for a Claude agent.
- **board.png**: re-take it only if the board's Obsidian view changed since it was taken; otherwise leave it and say so.
- The humanizer (`humanizer:humanizer`) runs over every changed paragraph and the PR description.

**Done when:**
- `grep -n "herdr shows working\|API error\|tell <slug> <file>" README.md docs/*.md commands/*.md` finds nothing that describes current behaviour.
- The rendered PNGs show `swarm.sh init` and an `auth` stop; the PR embeds both images.
- Every command in README's table exists (`swarm.sh <cmd>` runs its usage line, or the slash command file exists).
- The PR says the humanizer ran, and lists any paragraph it left unchanged on purpose.
- No plugin.json bump: release-agent-state carries it.

---
kind: code
status: blocked
blocked_by: [release-agent-state]
depends_on: [release-agent-state, build-outcomes]
touches: [bin/swarm.sh (close_agent's session archive, log-finding's declined form, a new decisions arm, usage line), tests/decisions_test.sh (new), tests/events_test.sh, commands/swarm.md (record declines), templates/ conductor text if it lives there, docs/method.md (§ The audit log), README.md (command table)]
---

# Keep what a System-1 decision model would learn from: session archives, declined findings, a decisions export

The user wants the swarm's logs to be training data for a small fast decision model (e.g. laya) that could
later pick a story's model and effort, or answer the swarm's other yes/no and choice decisions
(2026-10-13). Today: agents.tsv has role, model, effort and session; events.tsv has every command with
the tell kind; findings.tsv has fixed findings; `swarm.sh outcomes` joins them per build. Three gaps:

1. **Session logs expire.** Claude Code deletes session .jsonl files after `cleanupPeriodDays` (30 by
   default), and they hold every tool call and the model of every turn. When `close` closes an agent,
   copy its session .jsonl (found as cost_report finds it) to `.swarm/sessions/<date>-<agent>-<session>.jsonl`,
   gzip'd. `.swarm/` is git-ignored: the archive stays on the user's machine, is never committed and never
   uploaded. No redaction is attempted (a denylist redaction fails open); the README says the archive holds
   whatever the sessions held.
2. **Declined findings are not logged.** Only fixed findings reach findings.tsv; declines live in PR
   comments. Add `swarm.sh log-finding --declined <kind> <pr-url> <reason>`, written to findings.tsv with
   an outcome column (`fixed` | `declined`; old rows read as `fixed`), and make the conductor's review step
   (commands/swarm.md and the conduct briefs) log each decline with it.
3. **No export.** Add a read-only `swarm.sh decisions [--since YYYY-MM-DD]` that prints JSONL, one object
   per decision the swarm made, each with `decision` (model_choice | finding_accept | nudge | retry | close),
   `context` (the story's text at build time from git, or the finding text), `options`, `chosen`, and
   `outcome` (from `outcomes`: merged, tells, findings, attempts, cost). It reads only what the logs hold;
   a field it cannot fill is null, never guessed.

**Done when:**
- Closing a fixture agent with a session archives exactly one gzip'd copy under .swarm/sessions/; closing it again adds none; an agent with no session (codex, `-`) archives nothing. Shown red on the old code.
- `log-finding --declined` writes a row with outcome `declined`; `lessons` and `outcomes` keep counting only fixed ones (tests show both).
- `decisions` on a fixture prints valid JSONL with one object per model choice, finding (fixed and declined), nudge and close, with null where the logs hold nothing; it writes nothing (events_test's read-only check).
- README and docs/method.md § The audit log describe the archive (local only, unredacted, git-ignored), the declined form and `decisions`; humanizer ran over them and the PR description.
- No plugin.json bump.

**Not in scope:** training or running any model; changing how the swarm decides anything.

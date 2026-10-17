---
kind: lead
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [board/stories/<one new story per rule>.md]
easy: false
estimate_lines: 0
---

# Move the lead's remembered rules into swarm-dev as checks

The lead's memory holds rules it follows by hand: review agents use worktrees only, never `git checkout` uncommitted work, check reviewed behaviour against the user's recorded decisions before merging, and others. A rule kept only in one lead's memory does not reach another lead session or project. Several are already being moved by this epic (wait-pr, one merge path, board state out of git, next-names-blocking-lead-work).

The lead reads every `feedback` memory and lists each rule about how the swarm runs, in a table on this story: the rule, generalised and with nothing private in it (no names, repos outside swarm-dev, secrets or user content); where it already lands in swarm-dev (a story slug, or code with file:line); or the check it needs instead (a test, hook, `next` or `wait` behaviour, or a line in a brief or review prompt). Each rule that is not covered gets its own `kind: code` story in this epic, one check per story, under the size cap. A rule that is a matter of judgement and cannot be checked says so in the table. It stays in memory, and the lead decides whether it goes into commands/swarm.md as prose.

**Done when:**
- The table on this story covers every `feedback` memory that is about running the swarm, and gives each a story slug, a code location, or "judgement: stays in memory" with a reason.
- Each uncovered checkable rule has a story file in board/stories/ with `epic: safer-faster-swarm` and a Done when that fails without the check.
- No story or table row names a person, a private repo, or memory content beyond the generalised rule.

## The sweep (2026-10-17)

Rules about running the swarm, from the lead's feedback memories. Project decisions (cloud focus, mock design, CI spend, merge authority) are not swarm rules and are left out.

| Rule | Where it lands |
|---|---|
| Background waits fail loudly on a gh error | wait-pr |
| Merge only on a verified green head; no merge through scripts | merge-guard-hook, `swarm.sh merge` (ci_gate) |
| Codex at its limit is not a blocker | fallback-reviewer |
| Every PR gets codex and, for code, /code-review | code: conduct_brief and review_rule in bin/swarm.sh |
| Decline nits with a reason; one clean pass converges | code: `log-finding --declined nit`, commands/swarm.md |
| Never leave or wholesale-restore board edits in the main checkout | board-state-out-of-git, pr-removes-story |
| Do ready lead stories that block a build while waiting | next-names-blocking-lead-work |
| Put a timed check on every delegated build | code: stall_minutes, `wait --stall` |
| Escalation calls are the lead's | code: escalate and impossible blocks carry no **You:** step |
| Review agents run only in their own worktree; never checkout, restore or switch branches in the main checkout; guard `cd` in compound commands | **new: main-checkout-guard** |
| Never undo an edit with `git checkout <file>` (it drops all uncommitted work) | **new: main-checkout-guard** |
| Never override a recorded user decision, even with a stricter one | **new: review-prompt-checklist** |
| A check against a stand-in is not a check; a narrow sample is not a conclusion; a narrow audit is worse than none; new paths inherit unwritten rules; a zero value lies in a view; a silent fix looks like no fix | **new: review-prompt-checklist** |
| Never denylist a secret | env-allowlist covers the leak path; inspecting credential files is judgement and stays in memory |
| Fix the shared upstream cause first | judgement: stays in memory |
| Human prose goes through the humanizer | judgement: stays in memory (the docs stories already say it) |
| Tag builder memories with `lesson:` | retired by remove-lessons; the memory is deleted when it merges |

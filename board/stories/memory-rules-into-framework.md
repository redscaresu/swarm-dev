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

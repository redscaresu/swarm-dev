---
kind: code
status: ready
fix: true
depends_on: []
touches: [bin/lib/build.sh:review_round_line round-1 code-review, bin/lib/build.sh:review_brief code-review lines, tests/review_agent_test.sh:round-1 brief cases, docs/reference-building.md:review agent paragraph (§ Building) code-review sentence, docs/method.md:review sentence, AGENTS.md:review-agent bullet, docs/features.tsv:code-review rows]
estimate_lines: 80
easy: true
---

# The review agent runs codex alone, with no /code-review on round 1

**Why `fix: true`** (the user's decision at the v0.31.0 retro, 2026-11-17): review rounds were too slow
for what round 1's `/code-review` gave. Since v0.30.0 it raised 1,394 findings on 120 PRs and 109 of
them were acted on (8%); 1,285 were declined, each read and turned down. codex raised 238 on 56 PRs and
156 were acted on (66%) (counted from .swarm/findings.tsv's reviewer column). This ships as v0.31.1.

bin/lib/build.sh's review_round_line tells round 1 to run `/code-review <PR>` when the PR changes code,
and codex alone on later rounds. Make every round codex alone: round 1's line names codex only, and no
brief line asks for `/code-review`. Keep the reviewer column's `code-review` value readable in old
findings.tsv rows (flow, outcomes and retro still read them); no new row is written with it.

**Done when:**
- tests/review_agent_test.sh: the round-1 brief for a PR that changes code names codex and does not
  contain `/code-review`; with the change removed it contains `/code-review` (shown on a worktree copy,
  quoted in the PR)
- Later rounds' briefs are unchanged (codex alone)
- `swarm.sh flow`'s reviewers section still reads old `code-review` rows (an existing or new fixture
  case)
- AGENTS.md's review-agent bullet, docs/reference-building.md, docs/method.md and any docs/features.tsv
  row that names /code-review on round 1 say codex alone
- scripts/select-tests.sh --run passes

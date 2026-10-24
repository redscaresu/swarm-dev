---
kind: code
status: ready
depends_on: []
touches: [bin/lib/build.sh:conductor review rule, the review agent's brief (find where review-<slug> is briefed), tests/conduct_brief_test.sh]
estimate_lines: 80
easy: false
---

# Review stops at the first round with nothing worth fixing; /code-review runs once

Findings on 2026-10-24: `/code-review` 98 fixed and 232 declined (99% of the day's declines); codex 11 fixed and 3 declined. Since 2026-10-20: codex 62% fixed, `/code-review` 51%. Loops ran on after rounds the conductor declined in full: #444 had 16 declines in a row and was still open; #441 reached round 5. Each round costs about an hour. The user decided on 2026-10-24: stop a PR's review loop as soon as a round has nothing that gets fixed, or the conductor judges everything in it low value or a nit.

- The review agent runs `/code-review` only on a story's first review round; from round 2 on it runs codex alone (and the fallback when codex is skipped). The conductor tells it the round, counted as build.sh counts rounds today (a `tell <slug> findings`).
- The conductor rule in bin/lib/build.sh: a round whose findings the conductor fixes none of (each one declined as nit, low value, out of scope or wrong) is a pass. Merge at once after rebutting them in the PR and logging each with `log-finding --declined`. This replaces the round-4 rule. Keep the head check before a merge.
- Leave codex on every round and every board PR.

**Done when:**
- A test on the rendered review brief: round 1 asks for codex and `/code-review`; round 2 and later ask for codex only.
- A test on the rendered conductor brief: it says a round with nothing fixed is a pass to merge, and no longer has the round-4 rule.
- `make test` passes.

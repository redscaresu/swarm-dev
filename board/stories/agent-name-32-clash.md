---
kind: code
status: ready
depends_on: []
touches: [bin/lib/build.sh:review-agent name check, tests/review_agent_test.sh:name clash case, docs/reference-building.md:review agent paragraph name sentence]
estimate_lines: 80
easy: true
---

# review-agent refuses a name herdr would cut into another agent's

The machine-usable conductor's report (2026-11-15) found that herdr cuts agent names to 32 characters.
So `review-review-pane-closes-after-merge` and `review-review-pane-closes-after-handover` were the same
name, and `review-agent` refused #819 as "still reviewing" for two days while #828's review pane stayed
open. Confirm the 32-character cut first (herdr's own docs or a test against `herdr agent list`), and
write what you found in the PR.

When the agent name a command would start, cut to herdr's limit, equals the cut name of another running
agent of this project with a different full name, `review-agent` (and `swarm.sh agent`) refuses with a
line naming both agents and the limit, rather than reporting the other agent's state as this one's.
A name within the limit behaves as today.

**Done when:**
- tests/review_agent_test.sh: two slugs whose review agent names share the first 32 characters make the
  second `review-agent` refuse with a line naming both; with the check removed it reports "still
  reviewing" instead (shown on a worktree copy, quoted in the PR)
- Two short slugs still start two review agents
- docs/reference-building.md says agent names are compared at herdr's 32-character cut, and why
- scripts/select-tests.sh --run passes

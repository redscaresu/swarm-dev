---
kind: code
status: ready
depends_on: []
touches: [bin/lib/dropped_lines.py:expected copies count, tests/dropped_lines_test.sh:both-sides-added cases, docs/reference-merging.md:dropped-lines paragraph (§ Merging)]
estimate_lines: 90
easy: true
risk: high
---

# The dropped-lines check counts a line both sides added the same way once

swarm.sh merge's dropped-lines check (bin/lib/dropped_lines.py) reports a line as dropped when the merge's file has fewer copies of it than "the base side's copies, plus the PR side's, less the merge base's". When both sides added the same line, as when one change lands on main by a squash merge and on the PR branch by its own commit of the same story, that sum expects two copies. git's own merge keeps one, so the check reports a line that is still there.

This held PRs on 2026-11-13/14 that had lost nothing: #857 (9 lines of a paragraph both sides of merge 5e325b9 added, kept once) and #841 (4 lines both sides of merge cffccd3 added, through #835's squash on main and a65f9f4 on the branch). Each needed a person to read the lines and merge by hand.

For a line L in file F, where both sides added L (the base side has more copies than the merge base, and so does the PR side), expect max(base copies, PR copies), not their sum less the merge base's. Keep every other case as it is: a copy the base added that the PR side did not, and the merge then dropped, still prints. This check is a safety rail, so the change must not let a real drop through: prove each case below on a fixture.

**Done when:**
- tests/dropped_lines_test.sh: a fixture where main and the PR branch each add the same line L (the same commit content squashed on main and committed on the branch), and the PR's merge of main keeps one copy, prints nothing and exits 0
- A fixture where main adds L, the branch does not, and the merge drops it still prints L and exits 1
- A fixture where main adds L twice and the branch adds it once, and the merge keeps only one copy, still prints L once (short of max(2, 1) = 2)
- Every existing case in tests/dropped_lines_test.sh still passes
- The first case goes red with the change removed, and the second and third stay red with it in, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- docs/reference-merging.md's dropped-lines paragraph says a line both sides added is expected once
- scripts/select-tests.sh --run passes

---
kind: code
status: blocked
epic: merge-mechanics
depends_on: [upgrade-recorded-session]
needs: [upgrade-recorded-session (the merged upgrade_one fallback; its paragraph in docs/reference-merging.md ('Moving a running epic to a new version') and its tests/upgrade_test.sh cases; which this story edits next to.)]
touches: [bin/lib/lifecycle.sh:upgrade_list, bin/lib/lifecycle.sh:upgrade_tally, docs/reference-merging.md:Moving a running epic to a new version, docs/lead-by-hand.md:After a release, tests/upgrade_test.sh:closed agent cases]
estimate_lines: 90
easy: true
---

# upgrade skips closed agents and names them once (#694)

Needs from upgrade-recorded-session: its edits to the same docs/reference-merging.md paragraph and to tests/upgrade_test.sh (shared parts); start from its merged code. #694's other symptom: upgrade 'kept closed agents in its list' and took over an hour reading agents (issue #694). upgrade_list (lifecycle.sh:5165-5176) lists every claude agent herdr holds in a pane recorded here. One whose claude has exited is found only when its round reaches upgrade_idle (rc 2, die at lifecycle.sh:5250), and counts as left (upgrade_left, 4979), which makes upgrade exit 1. Before the first round, leave out each listed agent whose Claude session reads gone (upgrade_state, 5308-5333): first check in tests/upgrade_test.sh's herdr and claude stubs which state a closed agent has. Print one `skipped (closed): <names>` line. Skipped agents are never waited on or sent a key, are not counted in `upgrade done: <n> moved, <m> left`, and do not change the exit code. An agent whose state reads unknown stays in the list, waited on as today. Remove docs/lead-by-hand.md's 'After a release' block (73-78): its symptoms are fixed by this story and upgrade-recorded-session. Closed panes are the epic's case: upgrade_list already drops an agent whose pane herdr no longer lists, without a word (lifecycle.sh:5165-5176). Name those too: each Claude agent agents.tsv records whose pane is missing from a herdr list that was read successfully goes in the same `skipped (closed):` line. A herdr list that could not be read is not a closure: say so and skip nothing. Use the session state upgrade_state already reads for the agents it lists; add no per-agent herdr or claude read before the first round (#694 reported the slowness). Correction: upgrade_round already meets a gone session itself (lifecycle.sh:4862) and counts it as left; change that path to skip and name it, as well as the pre-round check.

**Done when:**
- tests/upgrade_test.sh: with three agents, one whose session reads gone, upgrade prints `skipped (closed): <that one>` once, restarts the other two, sends the closed one no key, and exits 0.
- tests/upgrade_test.sh: an agent agents.tsv records whose pane is missing from herdr's list is named in `skipped (closed):`, gets no wait, key or restart, and is not counted as left. A herdr list that fails to read names nobody as closed and says the list was not read.
- tests/upgrade_test.sh: the `upgrade done:` summary counts the skipped agent neither moved nor left.
- tests/upgrade_test.sh: an agent whose state reads unknown is still waited on (the existing case passes).
- docs/reference-merging.md says closed agents are skipped and named; docs/lead-by-hand.md has no 'After a release' block.
- The PR body shows the new cases red with the skip removed.

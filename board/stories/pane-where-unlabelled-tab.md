---
kind: code
status: ready
epic: deferred-700
depends_on: []
touches: [bin/lib/panes.py:pane_where, bin/lib/status_report.py:agent rows (pane_where call), bin/lib/agents.sh:agent_where_in, bin/lib/dash_render.py:tree_view (no-label heading), tests/where_test.sh:no-label tab case, tests/agent_labels_test.sh:no-label tab case, bin/lib/dash_render.py:agent rows (pane_where call, 263), docs/reference-logs.md:where row (917), docs/reference-building.md:status row (1116), docs/dash.md:tab lines (181, 199-200)]
estimate_lines: 70
easy: true
---

# where and status mark a tab herdr gave no label

#700 item 3 (#673 round 3). pane_where (bin/lib/panes.py:26-31) returns the tab record's name when herdr gives the tab no label, so status (status_report.py:27-29) prints 'tab <record>' and where (agents.sh:agent_where_in, :2863-2886) prints it as if herdr had that label. dash's tree already marks the case as '<record> (<tab id>)' (dash_render.py:617-620). Make status's agent rows and where mark the no-label case the same way the tree does, so a reader can tell swarm-dev's name from herdr's label. Keep the tree's own marking and dash's agent rows (dash_render.py:263) consistent with it. Update the pane_where and agent_where_in comments, and docs/running.md's where row if it describes the tab. Tests in tests/where_test.sh and tests/agent_labels_test.sh. Prove each new case fails with the old fallback restored, on a worktree copy.

**Done when:**
- tests/where_test.sh: with herdr giving the tab no label, where prints the tab marked as swarm-dev's name (with its tab id, as dash's tree does); with a label, the label alone
- tests/agent_labels_test.sh: status's agent row marks the no-label tab the same way
- Both cases go red with pane_where's bare record fallback restored, shown on a worktree copy
- docs/reference-logs.md's where row, docs/reference-building.md's status row and docs/dash.md say how a tab with no herdr label is shown.
- scripts/select-tests.sh --run passes

---
kind: code
status: ready
epic: deferred-700
depends_on: []
touches: [bin/lib/agents.sh:has_project_pane, bin/lib/agents.sh:next_pane (outside-project branch), tests/workspace_labels_test.sh:pane order cases, docs/reference-building.md:lead-agents workspace paragraph (:100-110)]
estimate_lines: 120
easy: false
---

# The lead-agents workspace keeps a project pane first

#700 item 12 (#645's deferred findings (b) and (c); (a) is dropped in deferred-700-list-read). The workspace's directory is its first pane's (herdr_workspaces). For an agent started outside the project, next_pane (bin/lib/agents.sh:293-360) keeps a pane at PROJECT_DIR ahead of it. But has_project_pane (:281-291) accepts any project pane in the workspace, not one ahead of every outside pane, so (b) once the kept pane or placeholder tab is closed, and (c) when a project pane was made after an outside pane, a later outside start trusts a workspace whose first pane is outside the project. Make the check ask whether the workspace's first pane is a project pane; when it is not and none can be put first, open the agent in HERDR_WORKSPACE_ID with the existing fallback message. Fix the lead_agents_lock and next_pane comments where they state the order rule, and docs/reference-building.md:106 ('while that pane is open'). Tests in tests/workspace_labels_test.sh. Prove each case fails with the old check restored, on a worktree copy.

**Done when:**
- tests/workspace_labels_test.sh: a lead-agents workspace whose first pane is outside the project (kept pane closed) gets no new outside agent; the agent opens in the lead's workspace with the fallback message
- A workspace whose project pane comes after an outside pane is treated the same way
- Both cases go red with has_project_pane's any-pane check restored, shown on a worktree copy
- docs/reference-building.md says what happens once the kept pane is closed; scripts/select-tests.sh --run passes

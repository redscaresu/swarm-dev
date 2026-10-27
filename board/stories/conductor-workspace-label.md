---
kind: code
status: ready
epic: workspace-labels
depends_on: []
touches: [bin/lib/build.sh:epic_workspace, bin/lib/build.sh:project_label (new), tests/workspace_labels_test.sh (new), docs/reference.md:Workspace labels (new), README.md:Workspace labels (new)]
estimate_lines: 150
easy: false
---

# Each conductor's workspace is labelled <project> · <epic>

epic_workspace (bin/lib/build.sh:1222-1233) finds or makes the herdr workspace under the bare label its caller passes (the epic, its parent for a split child, or backlog), so two projects' epics and every project's backlog share labels. Add project_label (build.sh, new, beside conductor_name :1239-1246): PROJECT_DIR's basename, plus a short hash of the path as conductor_name adds one, only when herdr lists a swarm workspace of that basename whose cwd is another directory. epic_workspace labels the workspace `<project label> · <label>` and finds a workspace by label and cwd; it reuses a workspace under the old bare label only when its cwd is PROJECT_DIR, so a conductor started before the upgrade keeps its own and never takes another project's. Close is unchanged: tab_ids reads a tab's workspace from its record (bin/lib/lifecycle.sh:1985-1993); check close and tidy on a relabelled workspace. Start a Workspace labels list in docs/reference.md and README.md.

**Done when:**
- tests/workspace_labels_test.sh (new), herdr stubbed, two projects in one fixture: each project's conductor for the same epic slug, and each backlog conductor, lands in its own workspace; two projects with one basename (/a/app and /b/app) get distinct labels; a bare-label workspace whose cwd is PROJECT_DIR is reused and one whose cwd is the other project is not. Each check fails with the old labelling or with reuse by label alone.
- tests/close_test.sh and tests/close_exact_tab_test.sh pass.

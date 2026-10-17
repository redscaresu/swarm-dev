---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [commands/plan-hld.md (delete), templates/docs/hld/ (delete), bin/swarm.sh:ROLE_GROUPS and policy, bin/lib/board.sh:next_step, bin/lib/build.sh:start_conductor, bin/lib/build.sh:hld_workspace, commands/swarm.md:plan-hld arm, docs/reference.md:HLD mentions, tests/removed_test.sh, tests/next_test.sh:plan-hld cases, tests/roles_test.sh]
easy: false
estimate_lines: 200
---

# Remove /plan-hld, the HLD file type and the hld-lead role

Builds on the split: next_step's plan-hld arm, ROLE_GROUPS and policy's hld-lead, start_conductor's workspace naming by hld: (hld_workspace, bin/swarm.sh:2990). Delete commands/plan-hld.md and templates/docs/hld/. An epic with an hld: key still plans, and the conductor workspace is named for the epic's parent:, else the epic. Existing HLD files stay as plain docs. Before deleting, copy infrafactory's board and .claude/swarm/config into a temp dir and run this branch's `SWARM_PROJECT=<copy> swarm.sh next` there, never in ../infrafactory, since commands write events.tsv and may pull; quote it in the PR.

**Done when:**
- grep finds no plan-hld or hld-lead in bin/, commands/, templates/ or skills/ (tests/removed_test.sh lists them).
- tests/next_test.sh: an epic with an hld: key and an HLD file present gets plan-epic, never plan-hld.
- The PR body quotes `next` on the infrafactory copy with no plan-hld step, and ../infrafactory/.swarm/events.tsv's mtime is unchanged.

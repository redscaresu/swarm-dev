---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [dash-three-defects, dash-golden-frames, dash-merge-gauges, fold-reports]
touches: [bin/swarm.sh:dispatch and usage header, bin/lib/dash.sh:dash args, bin/lib/dash.sh:dash_check (new), tests/fixtures/dash/two_projects.sh, tests/dash_check_test.sh (new), commands/swarm.md:release arm, docs/dash.md:check paragraph]
easy: false
estimate_lines: 250
---

# dash --check asserts each dash number against the command that owns it

Needs dash-three-defects (the fixes it guards), dash-golden-frames (tests/fixtures/dash/two_projects.sh), dash-merge-gauges (the running count) and fold-reports (flow owns cost). `swarm.sh dash --check` compares each figure dash shows, per project frame, with the command that owns it. The fields: agents and the running count against status; cost against flow's cost section; the lead's queue against lead_queue; needs-you and the epic list against next and status; merges today and the 7-day rate against events.tsv as flow reads it. It prints each mismatch and exits 1 on any. commands/swarm.md's release arm runs `swarm.sh dash --check` after each release, and docs/dash.md documents it.

**Done when:**
- tests/dash_check_test.sh: on the two-project fixture, for each listed field, the test runs the owning command and compares, and `dash --check` exits 0.
- The same test: reverting any one of dash-three-defects' fixes, or a status stub that disagrees, makes `dash --check` exit 1 naming the field.
- commands/swarm.md's release arm names `swarm.sh dash --check` (grep).

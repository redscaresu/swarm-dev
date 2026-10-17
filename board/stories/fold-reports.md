---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/swarm.sh:dispatch and usage header, bin/lib/reports.sh:cost_report, features_report, review_yield_report, bin/lib/reports.sh:flow_report, bin/lib/flow_report.py, bin/lib/flow_cost.py, flow_features.py, flow_reviewers.py (new, moved), docs/features.tsv:rows naming cost, features, review-yield, README.md:commands list cost, features, review-yield, docs/reference.md:cost, features, review-yield rows, skills/swarm-dev/SKILL.md:report commands, tests/cost_test.sh, tests/features_test.sh, tests/review_yield_test.sh, tests/removed_test.sh, tests/flow_sections_test.sh (new)]
easy: false
estimate_lines: 300
---

# cost, features and review-yield fold into flow, and flow runs each section from its own file

Builds on the split (cost_report, features_report, review_yield_report and flow_report in bin/lib/reports.sh and their .py files); board-prep has already reworded the two lead stories that ran cost and review-yield. bin/lib/flow_report.py runs every bin/lib/flow_*.py module in name order, passing the window (--since, --until, --epic), the log paths and outcomes' rows; a section that needs gh calls it itself. So later stories add a section as a new file and never edit flow_report or flow_report.py. The three reports become flow_cost.py (tokens and cost per role), flow_features.py (each docs/features.tsv feature's uses and delete? flag) and flow_reviewers.py (findings raised, fixed and declined per reviewer and kind, and rounds per PR). `swarm.sh cost`, `features` and `review-yield` keep their dispatch arms and each print one line naming the flow section and exit 0, for one release; their usage lines say the same. features.tsv rows that name the old commands name flow.

**Done when:**
- tests/cost_test.sh, features_test.sh and review_yield_test.sh run their fixtures through `swarm.sh flow` (with --since and --epic) and assert the same numbers as before.
- `swarm.sh cost`, `features` and `review-yield` each print where their numbers went and exit 0 (tests/removed_test.sh).
- tests/flow_sections_test.sh: a fixture bin/lib/flow_zz_test.py dropped into a copy of bin/lib prints its line in flow's output with no other file changed.
- tests/features_test.sh's 40-row floor still passes.

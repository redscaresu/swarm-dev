---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [fold-reports, subagent-cost]
touches: [bin/lib/flow_model_fit.py (new), bin/lib/report.py:rework_of, docs/features.tsv:model-fit row, docs/reference.md:§ flow model-fit, tests/model_fit_test.sh (new)]
easy: false
estimate_lines: 290
---

# flow prints a model-fit table: cost and effectiveness per model and story class

Needs fold-reports' section loader (a new bin/lib/flow_model_fit.py) and subagent-cost's columns. Rows are model and effort from outcomes, with a story counted against the model of its first build (an escalation to Fable stays under the starting model). Subagent rows per model show subagent cost and its share of build cost. Classes are kind, risk, a size bucket from estimate_lines (<=100, <=300, >300, none) and the top-level area of its touches (bin/, commands/, docs/, tests/, other). All four are read through story_text (bin/swarm.sh:1655-1660), the story's last version in git, because merged stories are deleted. Cells: stories built, cost per merged story, first-attempt merge rate, mean attempts, substantive findings per PR (fixed, not declined), rework and escaped findings, minutes from start to merge. A cell under 5 stories prints its count and no verdict. Rework is rework_of() in bin/lib/report.py: a merged PR that a later PR fixes within 7 days, where the later PR names it or log-finding --reviewer escaped points at it. Add it if your base lacks it; dataset and rework use the same one. No new store. features.tsv row.

**Done when:**
- tests/model_fit_test.sh: a fixture with 5 stories in one cell and 2 in another checks every column of the first and that the second prints its count and no verdict.
- The same test: a story whose file was deleted in a git commit still lands in its class; a story escalated to Fable counts under its starting model; a builder with subagent columns gives a subagent row with the right share; a fix 3 days later counts as rework and one 8 days later does not.

---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [fold-reports, dataset]
touches: [bin/lib/flow_predictions.py (new), tests/prediction_scores_test.sh (new)]
easy: false
estimate_lines: 110
---

# flow scores the planner's easy labels and size estimates against the dataset

Needs fold-reports' section loader (a new bin/lib/flow_predictions.py) and dataset's .swarm/dataset.jsonl. When the file is present, flow prints, per planner model, the precision and recall of easy against was_easy and the median and mean size-estimate error. With no file, it prints a line saying to run swarm.sh dataset.

**Done when:**
- tests/prediction_scores_test.sh runs `swarm.sh dataset` on dataset's fixture, then `swarm.sh flow`, and checks the precision, recall and estimate error per planner model; with no file the hint line prints.

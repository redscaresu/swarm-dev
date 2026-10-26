---
kind: docs
status: ready
epic: review-loop
depends_on: []
touches: [docs/features.tsv:review-owner row, board/stories/release-v0-30-0.md:reading step]
estimate_lines: 15
easy: true
---

# features.tsv row for review agents owning the loop, and its reading at v0.30.0

Add one row to docs/features.tsv (5 columns: feature, landed, metric, baseline, uses). The bar goes in the metric text, since the file has no bar column. The baseline has no minutes figure, so it is `unavailable:` with the 2026-10-24 text. The existing 'review agents' row (features.tsv:42) stays. Add a reading step to board/stories/release-v0-30-0.md, between its steps 1 and 2. It runs `swarm.sh flow --since <v0.29.0 tag date> --until <today>` and reads time_in_state's green_to_review_min p90 and the PR count it covers. It records both, against the 10-minute bar, in the release PR body and in board/retros/v0.30.0.md. Edit that story file; do not delete it (the brief's 'nothing else under stories/' is about deletions).

**Done when:**
- docs/features.tsv has a row: feature `review agents own the loop`, landed `review-loop`, metric `flow time_in_state: green_to_review_min per PR, p90 (bar 10 min)`, baseline `unavailable: green_to_review_min is conductor-hands-off's new column; 2026-10-24: seven green PRs carried one at a time`, uses `event:review-agent`; tests/features_test.sh passes.
- board/stories/release-v0-30-0.md has the reading step with that flow command and both places the value goes, and a Done when item that the reading is recorded; its front matter is unchanged.

---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/outcomes_join.py, templates/docs/stories/README.md:checks row, docs/reference.md:outcomes paragraph, tests/recurring_kinds_test.sh (new)]
easy: false
estimate_lines: 150
---

# outcomes flags finding kinds fixed on 3+ PRs in 30 days, with counts before and after their check

Builds on the split: bin/lib/outcomes_join.py and findings.tsv. After the rows, outcomes lists every kind fixed on 3 or more PRs in the last 30 days. A kind whose check story has merged (a story with `checks: <kind>` front matter, found in git the way story_text finds it) shows its 30-day count before and since that merge. This replaces lessons' candidates, which remove-lessons deletes after it. templates/docs/stories/README.md documents checks:.

**Done when:**
- tests/recurring_kinds_test.sh: a fixture with a kind on 3 PRs, one on 2 PRs and one older than 30 days flags only the first; with a merged checks: story for it, its before and after counts print.

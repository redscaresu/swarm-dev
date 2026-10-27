---
kind: code
status: blocked
epic: dev-rules-docs
depends_on: [env-line-docs-patch, docs-check-in-builder]
needs: [env-line-docs-patch: the merged env: line fix, named as the line's example, docs-check-in-builder (review-loop): review_checklist as it leaves it]
touches: [bin/lib/build.sh:review_checklist, tests/epic_briefs_test.sh:review checklist line]
estimate_lines: 25
easy: true
---

# review_checklist: docs move with behaviour, with the env: line as its example

Uses env-line-docs-patch's merged PR as the example, and review_checklist as review-loop's docs-check-in-builder leaves it (it moves the docs-misstate-code check out). review_checklist (bin/lib/build.sh:736-760) gains one line: a PR that changes what a user runs, sees or must do and does not update README.md, docs/ or the command text in the same PR is a finding; example: the env: line (AGENTS.md, README.md), which drifted from the code until that PR.

**Done when:**
- tests/epic_briefs_test.sh renders a review brief and finds the line with its env: example; it fails when the line is removed.

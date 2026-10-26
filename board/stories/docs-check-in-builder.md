---
kind: code
status: ready
epic: review-loop
depends_on: []
touches: [bin/lib/build.sh:story_brief, bin/lib/build.sh:review_checklist, tests/review_test.sh:CHECKLIST, tests/epic_briefs_test.sh:builder brief checks]
estimate_lines: 60
easy: true
---

# Move the docs-misstate-code check from the review checklist to the builder

Front matter: `checks: docs-misstate-code`, so outcomes measures the kind from this merge. The check #417 added (2026-10-23) is review_checklist's re-read line (build.sh:745). A review-time check raises the fixed count; it did not cut the kind. Replace it: story_brief tells the builder, before it pushes, to re-read the header comment, error text and every README, doc, command or skill line that names each function, flag or error message the diff changes, and fix the ones that no longer match. Drop the re-read line from review_checklist; keep the exception line (a misstating line outside the touches is a finding). Merge before less-noise's builder-brief story (bin/lib/build.sh:story_brief) and before its docs-move-with-behaviour story (bin/lib/build.sh:review_checklist).

**Done when:**
- tests/epic_briefs_test.sh pins the re-read step in a builder's brief.
- tests/review_test.sh's CHECKLIST matches review_checklist with the re-read line gone and the exception line kept.
- Removing the new story_brief line turns the epic_briefs_test check red (falsified once, noted in the PR).

---
kind: code
status: ready
epic: review-yield
depends_on: []
touches: [bin/lib/flow_reviewers.py:block 1 (deferred column), tests/review_yield_test.sh:block 1 fixture (H1, B1, deferred case), docs/reference-logs.md:reviewers section (first block columns), bin/lib/reports.sh:reviewers entry of the flow comment (414-416)]
estimate_lines: 60
easy: true
---

# flow's reviewers block 1 gains a deferred column, so a demoted or capped kind's findings sent to the builder can be told from those held back

No depends_on. Today block 1 counts a deferred finding as declined with no split (bin/lib/flow_reviewers.py:11-24), so neither the round cap nor demote_kinds can show its effect per kind. Read rows with finding_rows(..., width=7) so the reason (field 7) is there, count declined rows whose reason is deferred per (reviewer, kind) key, and append a deferred column after rework: header reviewer kind raised fixed declined decline_rate rework deferred. Append, never reorder: decline_rate keeps its meaning (docs/features.tsv:13 reads it) and tests/rework_test.sh:79 cuts field 7 for rework. A row with no reason field (4-, 5- and 6-field rows, before the deferred reason existed) counts 0 deferred, and the docs say so (rules.md: a zero shown to a person says what it means). --epic narrows it as it narrows the rest. Update the reviewers paragraph in docs/reference-logs.md (:695-700) and the reviewers entry of the flow comment in bin/lib/reports.sh (:414-416); run humanizer over the changed prose and the PR body. Tests: extend tests/review_yield_test.sh's block 1 fixture (H1, B1 at :65-72) with the column and a deferred case, shown failing with the count removed.

**Done when:**
- flow's reviewers block 1 header reads reviewer kind raised fixed declined decline_rate rework deferred, and review_yield_test.sh pins it.
- On a fixture with one codex duplicate-code row fixed, one declined as nit and one declined as deferred, the codex duplicate-code row reads 3 1 2 67% 0 1, and the codex all, all duplicate-code and all all rows each count the deferred one; review_yield_test.sh pins these rows exactly.
- On the existing fixture, every row keeps its first seven fields as today and reads 0 deferred, 4-, 5- and 6-field rows included.
- tests/rework_test.sh passes unchanged.
- The PR body pastes the FAIL line from review_yield_test.sh with the deferred count removed, run in a copy of the worktree.
- docs/reference-logs.md's reviewers paragraph and reports.sh's reviewers comment name the column and say a row with no reason counts 0; the PR says humanizer ran over that prose.

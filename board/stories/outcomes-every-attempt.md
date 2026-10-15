---
kind: code
status: blocked
blocked_by: [finding-reviewer-column]
epic: training-export
depends_on: [finding-reviewer-column]
touches: [bin/swarm.sh:outcomes_report, tests/outcomes_test.sh, tests/decisions_test.sh]
---

# outcomes gives each build the PR that build made, not the slug's newest

Absorbed as is from board/stories/outcomes-every-attempt.md (add `epic: training-export`). The PR comes from one `gh pr list --head story/<slug> --state all --limit 1` per slug (bin/swarm.sh:1046-1056), so every build of a retried story shows the newest PR. Keep one row per builder; take each builder's PR from its own session log: the last github pull URL there whose PR is one of the slug's PRs (one `gh pr list` without --limit). No match: empty PR. Session log gone and the slug has exactly one PR: that PR, as today. Dates are not used.

**Done when:**
- tests/outcomes_test.sh: a slug with two builder lines and stub gh returning #1 CLOSED and #2 MERGED (each session log prints its own URL) prints row 1 with #1 CLOSED and row 2 with #2 MERGED, attempts 1 then 2, each with its own model.
- Two builders whose logs both name the one PR both show it; a first builder whose log names no PR shows an empty PR and the second its own, both started the same day.
- A PR URL in the log for another head is not taken.
- tests/decisions_test.sh: for the two-PR case the first decision has merged false and the second merged true; existing rows unchanged.
- One builder, one PR prints as today, including with its session log missing.
- The PR shows the new checks failing with `--limit 1` restored; shellcheck and every tests/*_test.sh pass.

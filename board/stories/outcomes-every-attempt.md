---
kind: code
status: ready
touches: [bin/swarm.sh:outcomes_report, tests/outcomes_test.sh, tests/decisions_test.sh]
---

# outcomes gives each build the PR that build made, not the slug's newest

`outcomes` prints one row per builder line in agents.tsv, and `decisions_report` relies on that one-to-one match. But the PR comes from `gh pr list --head story/<slug> --state all --limit 1`, so every build of a retried story is shown with the newest PR. A first attempt whose PR was closed unmerged reads as merged, and the training record loses how that attempt ended. Keep one row per builder, and take each builder's PR from its own session log (session_log already finds it): the last `https://github.com/<owner>/<repo>/pull/<n>` URL in that log whose PR has head `story/<slug>`, checked against the slug's PRs from one `gh pr list --head story/<slug> --state all` call (no `--limit 1`). A builder whose log names none of the slug's PRs gets an empty PR, not a guess; only when its session log is gone (Claude Code deletes old ones) and the slug has exactly one PR does it get that PR, as today. Dates are not used, since agents.tsv records only the day.

**Done when:**
- tests/outcomes_test.sh: a slug with two builder lines and a stubbed `gh` returning two PRs (#1 CLOSED, #2 MERGED; each builder's fixture session log prints its own URL) prints the first row with #1 and CLOSED and the second with #2 and MERGED. Each row keeps its own model and attempts (1, then 2).
- Two builder lines with one PR between them both show that PR when both session logs name it; a first builder whose log names no PR shows an empty PR and the second shows its own, even when both builds started the same day.
- A PR URL in the log for another head (a PR the builder only read) is not taken.
- tests/decisions_test.sh: for the two-PR case above, the first decision has merged false and the second merged true; existing rows are unchanged.
- A slug with one builder and one PR prints as today, including when that builder's session log is missing.
- The PR shows the new checks failing with `--limit 1` restored; shellcheck and every tests/*_test.sh pass.

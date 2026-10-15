---
kind: code
status: ready
touches: [bin/swarm.sh:outcomes_report, tests/outcomes_test.sh, tests/decisions_test.sh]
---

# outcomes gives each build the PR that build made, not the slug's newest

`outcomes` prints one row per builder line in agents.tsv, and `decisions_report` relies on that one-to-one match. But the PR comes from `gh pr list --head story/<slug> --state all --limit 1`, so every build of a retried story is shown with the newest PR. A first attempt whose PR was closed unmerged reads as merged, and the training record loses how that attempt ended. Keep one row per builder; fetch all of a slug's PRs (oldest first, with createdAt) and give the slug's k-th builder the oldest PR not created before its start day that an earlier builder of the slug has not taken. A builder that opened no new PR (a rebuild that reused the open one) gets the PR the slug's previous builder had.

**Done when:**
- tests/outcomes_test.sh: a slug with two builder lines and a stubbed `gh` returning two PRs (#1 CLOSED, created on the first build's day; #2 MERGED, created on the second's) prints the first row with #1 and CLOSED and the second with #2 and MERGED. Each row keeps its own model and attempts (1, then 2).
- Two builder lines with one PR between them both show that PR.
- tests/decisions_test.sh: for the two-PR case above, the first decision has merged false and the second merged true; existing rows are unchanged.
- A slug with one builder and one PR prints as today.
- The PR shows the new checks failing with `--limit 1` restored; shellcheck and every tests/*_test.sh pass.

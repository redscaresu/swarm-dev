---
kind: code
status: blocked
blocked_by: [finding-reviewer-column, outcomes-attempt-events]
epic: review-yield
depends_on: [finding-reviewer-column, outcomes-attempt-events]
touches: [bin/swarm.sh:review_yield_report (new), bin/swarm.sh:dispatch (review-yield arm), bin/swarm.sh:usage header (review-yield line), bin/swarm.sh:READ_ONLY_COMMANDS, tests/review_yield_test.sh (new), tests/events_test.sh (RO_EXPECTED), README.md (command table), docs/method.md (read-only list :362-365; review-yield paragraph after decisions)]
---

# `swarm.sh review-yield [--since YYYY-MM-DD]` prints findings raised, fixed and declined and the decline rate per reviewer and kind, and review rounds per PR

New read-only review_yield_report in the REPORT_PY style. --since is validated as outcomes does (bin/swarm.sh:990-993). Block 1, TSV `reviewer kind raised fixed declined decline_rate` from finding_rows (6 columns after finding-reviewer-column), rows dated on or after since: per reviewer an `all` row then its kinds by declined descending, and a final `all all` row; decline_rate is declined/raised as a whole percent. Block 2, after a blank line, TSV `prs rounds rounds_per_pr max_rounds`: sum outcomes' tells_findings per pr_key(pr) over builds with a PR, read from outcomes_report's rows by column name as decisions_report does (:1081, :1093-1099), so no second events or gh parser. Rounds are not split by reviewer: a tell line names none. With no agents.tsv, block 2 is `0 0 0 0` and block 1 still prints. Dispatch arm, usage header line, READ_ONLY_COMMANDS (:4271) and tests/events_test.sh RO_EXPECTED (:137), a README command-table row (:80), method.md's read-only list (:362-365) and one paragraph after decisions (:385-394). The dispatch, usage header and READ_ONLY_COMMANDS lines are also edited by codex-time-limit, wait-until-report, merge-command, board-pr-command, story-warns-cross-epic-touches and tell-conductor-note: separate arms and lines, rebase only.

**Done when:**
- tests/review_yield_test.sh (new, gh stub as tests/outcomes_test.sh does): a findings fixture with 4-, 5- and 6-field rows prints every block-1 row pinned, including the 4- and 5-field rows under `unknown`, a codex kind with 1 fixed and 2 declined as `3 1 2 67%`, and an `all all` row equal to the fixture totals.
- `--since 2026-10-01` drops a row dated 2026-09-30 from every count it was in; `--since 2026-1-5`, a bare `--since` and `--bogus` exit non-zero with the usage line.
- Rounds: builders for slugs a and b, the gh stub giving a PR #1 and b PR #2; events.tsv gives a two ok tell:findings, one ok bare `tell`, one refused tell:findings and one ok tell:nudge, and b none: block 2 is `2 3 1.5 3`.
- With no agents.tsv it exits 0, prints block 1 and block 2 as `0 0 0 0`; findings.tsv and events.tsv are byte-identical after any run, and RO_EXPECTED holds review-yield.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs/commands prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Depends on outcomes-attempt-events (training-export), so per-attempt tells and PRs are right. Fixtures: two attempts sharing one PR with three findings tells total report three rounds; two attempts with distinct PRs each get only their own tells.
- Block 1 has a per-kind row across reviewers (`all <kind>`) as well as per (reviewer, kind), per reviewer and overall.
- `--epic <slug>` limits the report to that epic's PRs and lists the PR URLs it counted, so the tuning can prove coverage.

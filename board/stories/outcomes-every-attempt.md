---
kind: code
status: ready
touches: [bin/swarm.sh:outcomes_report, tests/outcomes_test.sh]
---

# outcomes lists every PR a story had, not only the newest

`outcomes_report` looks up a slug's PR with `gh pr list --head story/<slug> --state all --limit 1`, so a story that was built, closed unmerged and built again shows only its last PR. The earlier attempts drop out of the record, and that record is training data for the model and effort router. Give each PR of a slug its own row (number, state, model, effort as today), oldest first, so a retried story shows every attempt and how it ended.

**Done when:**
- tests/outcomes_test.sh: with a stubbed `gh` returning two PRs for one slug (one CLOSED, one MERGED), `outcomes` prints two rows for that slug with both PR numbers and both states, the CLOSED one first.
- A slug with one PR prints one row as today.
- The PR shows the new check failing with `--limit 1` restored; shellcheck and every tests/*_test.sh pass.

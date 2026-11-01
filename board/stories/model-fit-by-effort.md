---
kind: code
status: ready
epic: stalls-and-effort
depends_on: []
touches: [bin/lib/flow_model_fit.py:by_risk block (new, after the cell rows), tests/model_fit_test.sh:by_risk cases, docs/reference-logs.md:Flow and features (model_fit paragraph), docs/reference-logs.md:Commands (swarm.sh flow row, model_fit summary), docs/features.tsv:effort trial row (new)]
estimate_lines: 70
easy: true
---

# flow model_fit: a row per model, effort, kind and risk over every size and area

No depends_on. model_fit crosses model and effort with kind, risk, size and area, and prints only a count for a cell under MIN_STORIES (5) (bin/lib/flow_model_fit.py:13, 62-70), so a trial wave of a few risk: high stories split over sizes and areas shows no rates. After the cell rows and before the subagents block, add a block after a blank line whose header begins `by_risk` (not `model`, as the subagents block begins `subagents`), one row per model, effort, kind and risk over every size and area, with the same measure columns, built by the same cell() so MIN_STORIES and every column rule hold unchanged. No new flag or command. Docs: reference-logs.md § Flow and features, the model_fit paragraph, says what the block is and that it uses the same 5-story floor; the `swarm.sh flow` row's model_fit summary in reference-logs.md § Commands names it. Humanizer over the changed docs. Proof: with the block removed in a copy, the new checks go red. Add the docs/features.tsv row for the effort trial (model_fit by_risk: cost per merged story and first-attempt merge rate for risk: high code), as the HLD asks of each measured behaviour (HLD:123).

**Done when:**
- tests/model_fit_test.sh: a fixture of five opus/high code/high stories across at least two size buckets prints each of their main-table cells with its count and `-`, and a by_risk row `opus high code high` with stories 5 and cost_per_merged_usd and first_attempt_merge_rate equal to the values the fixture fixes.
- tests/model_fit_test.sh: a by_risk row with 4 stories prints its count and `-` in every other column.
- tests/model_fit_test.sh: the existing cell and subagents checks still pass, and the by_risk header line differs from the main table's header.
- With the block removed in a copy of flow_model_fit.py, the new checks fail; the PR says so.
- docs/features.tsv has the effort trial row, and tests/features_test.sh passes.
- scripts/select-tests.sh --run and python3 -m py_compile bin/lib/*.py pass.

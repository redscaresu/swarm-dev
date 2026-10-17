---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/outcomes_rows.py, bin/lib/outcomes_join.py, docs/features.tsv:subagent-cost row, tests/subagent_cost_test.sh (new), tests/fixtures/subagent/ (new)]
easy: false
estimate_lines: 140
---

# outcomes shows builder subagents' tokens and cost by model, apart from the builder's own

Builds on the split: bin/lib/outcomes_rows.py and bin/lib/outcomes_join.py. Do not open real session logs: they can hold credentials. Read subagent turns in both shapes Claude Code may write, each with a fixture: turns with parent_tool_use_id set inside the builder's session .jsonl, and subagents/*.jsonl beside it. outcomes gets two columns at the end: subagent cost, and subagent cost per model (model:usd, comma-joined). The builder's cost column keeps only its own turns. Rows stay one per builder line, because flow lines them up with agents.tsv (bin/swarm.sh:1366). builder_subagent_model stays empty. model-fit-table shows these per model in flow. features.tsv row.

**Done when:**
- tests/subagent_cost_test.sh: fixture builder sessions in both shapes, with Opus turns and Haiku and Opus subagent turns, give the right subagent cost and per-model split; the builder's own cost excludes them; the row count equals agents.tsv's builder lines.

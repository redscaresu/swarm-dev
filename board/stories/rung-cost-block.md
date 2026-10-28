---
kind: code
status: ready
epic: ladder-cost
depends_on: []
touches: [bin/lib/flow_cost.py:per-rung block (new), bin/lib/outcomes_join.py:step-up outcome join, tests/cost_test.sh:per-rung cases, docs/reference.md:cost section, docs/reference.md:ladder examples, docs/features.tsv:ladder row]
estimate_lines: 220
easy: false
---

# flow's cost shows tokens per ladder rung and per step-up, with each step-up's outcome

Add a per-rung block to flow's cost section (bin/lib/flow_cost.py, which today keys by role only and keeps no agent name, :1-62). For each step-up in the window (events.tsv `escalate` lines whose outcome starts `ok (`, e.g. `ok (findings-3: opus -> fable)`; the trigger is the label before the colon), sum the tokens of the story's builder sessions on each rung: agents.tsv rows (date, role, name, kind, model, effort, session) for that story's name, grouped by the model column, priced with session_usage as the role table is. Then say whether the build merged, went to the lead or failed, read from outcomes' rows for the story (bin/lib/outcomes_join.py), not from events alone: a PR merged on GitHub or by another run has no `merge` event of this run's. A build outcomes has no row for yet reads as open. Print a second small table: per rung, how many builds in the window reached it, and their share of all builds. The count is per rung: findings_told counts since the newest start (bin/lib/agents.sh:1679), and the docs say so.

Docs: reference.md's cost section names the new block; its ladder examples say the default `step_up_findings` is 3 and that the trigger label follows the value (`findings-3`, built at bin/lib/lifecycle.sh:582). docs/features.tsv gets a row for the ladder threshold, metric `flow cost: tokens per rung and share of builds reaching each rung`, with the 0.27 baseline (#480's four rounds at xhigh, about 6% of the week, the 0.28 HLD's Appendix D). Run the humanizer over the new docs prose.

Do not change bin/swarm.sh's `step_up_findings` default (3, :192), this board's .claude/swarm/config, or `top_rung_rounds` (2; the config still refuses 1, bin/swarm.sh:241-244). Never run flow against the real repo in a loop: one `flow --since <today>` after `gh api rate_limit`.

**Done when:**
- tests/cost_test.sh feeds a fixture events.tsv and agents.tsv with two step-ups (one `findings-3` whose PR outcomes reads as merged with no `merge` event, one `stalled` that went to the lead) and three rungs, and the cost section prints one row per step-up with its trigger, tokens per rung and outcome, and the reach table with the right counts and shares; it fails when the block is dropped or a step-up's outcome is wrong.
- A window with no step-up prints the block's header and `none`, and the section still exits 0 (tests/flow_sections_test.sh stays green).
- reference.md's cost section and ladder examples, and docs/features.tsv's ladder row, say what the scope says; `make test` and shellcheck pass.

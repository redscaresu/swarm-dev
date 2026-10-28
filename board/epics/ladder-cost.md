---
status: active
hld: 2026-10-25-swarm-dev-0-28
stage: v0.30.0
depends_on: [review-loop, conductor-hands-off, less-noise, merge-holds, fixes-027]
---

# ladder-cost

flow's cost shows tokens per ladder rung and per step-up with each step-up's outcome, so the v0.31.0 retro can weigh the threshold and the top rung. HLD Goal 6, Design § Ladder threshold and § Top-rung cost.

Measure first (v0.28.0 retro, 2026-10-26): step_up_findings stays 3 on this board too. In v0.28.0 the 5 findings-3 step-ups to Fable still took 3 to 4 more rounds each, so a lower threshold would mostly buy Fable sooner. The retro decides on 2 from this epic's figures.

**Done when:**
- flow's cost section has a per-rung block: for each step-up (events.tsv step-up lines, trigger from the marker), tokens on each rung (agents.tsv model column joined by agent name; bin/lib/flow_cost.py:1-62 today keys by role only and keeps no name) and whether the build then merged, went to the lead or failed (from outcomes); tests/cost_test.sh pins it on a fixture with two rungs and one step-up.
- bin/swarm.sh:192's default stays 3 and this board's .claude/swarm/config does not set step_up_findings.
- reference.md's cost section and ladder examples name the new block, and say the default is 3 and that the trigger label follows the value (`findings-3`; bin/lib/lifecycle.sh:582 builds it).
- docs/features.tsv has a row for the ladder threshold with metric `flow cost: tokens per rung and share of builds reaching each rung` and the 0.27 baseline (#480's four rounds at xhigh, about 6% of the week, Appendix D); the retro reads flow's review_loops, reviewers and cost against it.
- top_rung_rounds stays 2 and the config still refuses 1 (bin/swarm.sh:241-244).

**Out of scope:**
Changing the plugin default or this board's step_up_findings; Fable at high on the ladder; a usage gate; changing how the top rung runs; reading the figures (the retro's).

**Constraints:**
- The count is per rung (findings_told counts since the newest start, bin/lib/agents.sh:1679): the docs say so.
- Never run flow against the real repo in a loop or over days (Appendix C): one --since <today> after gh api rate_limit.
- tests/flow_sections_test.sh: a new flow section is a new bin/lib/flow_*.py or an edit to flow_cost.py; a raising section fails flow; lib_path_test (-I, SWARM_LIB).
- Touch docs/features.tsv as `docs/features.tsv:ladder row`; bash 3.2, shellcheck, make test; humanizer over docs prose.

**Areas:** bin/lib/flow_cost.py, bin/lib/outcomes_join.py:step-up outcome join if needed, docs/reference.md:cost and ladder sections, docs/features.tsv:ladder row, tests/cost_test.sh

**Your part:**
Lead: the kind: lead story that edits .claude/swarm/config, after the cost block merged (story-level depends_on). **You:** merge the held config PR (merge --board refuses a file outside board/, merge.sh:279-283, and swarm.sh merge holds a .claude/ change for you under merge-holds' hold). The threshold itself was your 2026-10-25 ask and the retro revisits it. The cut is the release story's.

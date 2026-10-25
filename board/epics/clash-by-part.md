---
status: active
hld: 2026-10-25-swarm-dev-0-28
stage: v0.28.0
depends_on: []
---

# No false clash holds from a bare file

No false clash holds from a bare file: the clash check compares a part by its first token, a bare file clashes only with the same bare file, /plan-epic writes file:part and its split critic flags a bare file, and the epic and backlog paths each have a test. HLD Goal 7, Design § Clash check by part.

**Done when:**
- overlap() in bin/lib/touches_rows.py:65-66 holds two entries only when file matches and the parts' first tokens match, or both parts are empty; a test shows `bin/swarm.sh` against `bin/swarm.sh:load_config` does not hold and `bin/swarm.sh:load_config and the dispatch` against `bin/swarm.sh:load_config` does.
- One test per path: swarm.sh story --strict between stories of two epics, and between two backlog stories (touches_rows.py:92 already applies the same rule to both; the HLD's 'backlog stories checked too' ships as the test, not a change).
- The conductor brief's clash_rule (bin/lib/build.sh:1119-1135), AGENTS.md:105-106, docs/method.md:22 and reference.md state the part rule; doc_check passes.
- commands/plan-epic.md tells planners to write file:part with the part starting with a function or section name, and the split critic (commands/plan-epic.md:41-60) reports a bare-file touches as a finding; tests/plan_epic_test.sh and tests/split_critic_test.sh pin it.
- Fixtures in tests/stacked_test.sh, tests/stacked_status_test.sh, tests/epic_overlap_test.sh and tests/flow_holds_test.sh that relied on a bare-file hold are rewritten to a real clash, and make test passes.
- docs/features.tsv has a clash row with metric `flow holds: touches-clash holds per 10 PRs` and the 2026-10-24 baseline (four false holds, Appendix A), and the epic file names the cost to watch: flow's merge_ins (conflicts). Both are read at the v0.29.0 release story and the retro.

**Out of scope:**
A smarter part match than the first token; changing how a builder resolves a merge conflict (it merges main, as today); the within-epic wave order beyond rewording.

**Constraints:**
- swarm-dev's AGENTS.md names no shared files (AGENTS.md:105-107 says the lead edits the files a project's AGENTS.md names; this one names none), so the AGENTS.md clash line is ordinary story work, touched as `AGENTS.md:rules that are not negotiable`.
- Within-epic clash is conductor prose, not code (survey: build.sh clash_rule); both places change in one story or with a depends_on.
- tests/epic_overlap_test.sh, tests/backlog_test.sh, tests/conduct_backlog_test.sh cover the paths; python helpers run under -I with SWARM_LIB (tests/lib_path_test.sh).
- Touch docs/features.tsv as `docs/features.tsv:clash row`.
- bash 3.2, shellcheck, make test; humanizer over the commands/ and docs prose.
- Order: this epic's AGENTS.md story goes after test-speed's 'Before you open a PR' story (AGENTS.md is a shared hot file, commands/plan-epic.md:69).

**Areas:** bin/lib/touches_rows.py:overlap, bin/lib/build.sh:clash_rule, commands/plan-epic.md:touches and split critic, docs/method.md:clash line, docs/reference.md:clash rule, docs/features.tsv:clash row, AGENTS.md:rules that are not negotiable, tests/ (epic_overlap, backlog, stacked, flow_holds, plan_epic, split_critic)

**Your part:**
None; the cut is the release story's (stage-gating's constraints).

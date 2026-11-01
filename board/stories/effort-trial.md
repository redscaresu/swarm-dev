---
kind: lead
status: blocked
epic: stalls-and-effort
depends_on: [risky-effort-key, model-fit-by-effort, stall-live-test-run]
needs: [risky-effort-key (the risky_effort config key; which sets code-risky's effort to high), model-fit-by-effort (model_fit's by_risk rows; which give the trial's few stories their cost and first-attempt rates), stall-live-test-run (the fixed stall check in the installed plugin; so no false stall step-up adds cost to trial or comparison builds)]
touches: []
estimate_lines: 3
easy: false
---

# Lead: Run risk: high code builds at effort high for one wave, then compare with flow model_fit

Needs from risky-effort-key: the `risky_effort` key, the only way to run code-risky at high (policy() hard-codes xhigh at bin/swarm.sh:434). Needs from model-fit-by-effort: the by_risk rows. Needs from stall-live-test-run: the fixed stall check, so trial and comparison builds are not stepped up by a false stall. The installed swarm.sh must know risky_effort before the config sets it: an older one dies on `unknown key` (load_config's `*)` arm) and stops every swarm.sh call. A patch release cannot carry it: patches carry only fixes (commands/swarm.md:637; HLD:298), and risky-effort-key and model-fit-by-effort are features. Steps. (1) **You:** choose when the trial runs: (a) cut an early minor release mid-stage with whatever v0.31.0 has merged by then, which breaks the HLD's 'each release holds exactly its stage' (HLD:621-622) for this stage; or (b) run it in the first build after v0.31.0 ships. Record the answer here. (2) **You:** after that release, update the plugin and restart the lead session. (3) Lead: check the installed `swarm.sh config risky_effort` prints `xhigh` and `swarm.sh policy code-risky` prints `claude opus xhigh`. Then open an ordinary PR (not a board PR: `merge --board` refuses any file outside board/, bin/lib/merge.sh:1066) that adds `risky_effort = high`, with a dated comment, to .claude/swarm/config. (4) **You:** merge it by hand. (5) Lead: name the cohort here when it merges: the risk: high code stories of the one wave that starts next. The trial is that one wave (the epic's agreed limit). Check the first cohort build's agents.tsv line reads `opus high`. The wave ends when every cohort story has merged or closed. (6) Lead: an ordinary PR removes the line. **You:** merge it. (7) Lead: `gh api rate_limit`, then run `swarm.sh flow --since 2026-10-28 --until 2026-10-31` (the v0.30.0 build) and `swarm.sh flow --since <trial start> --until <trial end>`, one at a time, once each. Record the by_risk rows `opus xhigh code high` and `opus high code high` from both: stories, cost_per_merged_usd, first_attempt_merge_rate, mean_attempts. Say beside them that the v0.30.0 rows ran on the 0.29 plugin, with false-stall step-ups and no round cap, so the comparison is rough. If the cohort has fewer than 5 stories, by_risk prints no rates (bin/lib/flow_model_fit.py:62-64): record `insufficient data: <n> stories` and the per-story figures instead; a second wave needs the user's yes, recorded here. (8) **You:** decide from the figures: keep high for risk: high code stories (a follow-up story changes the default) or stay at xhigh. Record the decision here. (9) Lead: stall-live-test-run removes the only hang guard on a test run (a run blocked on a ~/.swarm/test-cap slot included). File a GitHub issue for a warn-only line past N x stall_minutes, and link it here.

**Done when:**
- The user's choice of when the trial runs is recorded here.
- The PR adding `risky_effort = high` and the PR removing it have both merged, with dates recorded here, and `swarm.sh policy code-risky` prints `claude opus xhigh` again.
- The cohort is named here, and every cohort story merged or closed before the line was removed.
- Both flow runs' by_risk rows, or `insufficient data` with per-story figures, are recorded here.
- The user's keep or revert decision is recorded here.
- The hang-guard issue is filed and linked here.

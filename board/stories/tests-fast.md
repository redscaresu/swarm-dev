---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [Makefile:test target, .github/workflows/ci.yml:test job, bin/lib/agents.sh:start_agent, bin/lib/agents.sh:deliver_prompt, bin/lib/merge.sh:watch_prs, bin/lib/merge.sh:MERGE_POLL, MERGE_CI_GRACE, bin/lib/build.sh:send_goal, bin/lib/dash.sh:dash_watch, bin/swarm.sh:codex_review, tests/*_test.sh:isolation lines, tests/sleep_scale_test.sh (new), README.md:§ develop test line]
easy: false
estimate_lines: 170
---

# make test runs the suite in parallel with each file isolated, and swarm.sh's fixed sleeps scale by a variable tests set near 0

Builds on the split. There is no make test (the Makefile has only hooks). Add a test target that runs tests/*_test.sh with xargs -P, prints each file's name, result and seconds, and fails if any file fails; ci.yml's test job runs it. Fifteen test files never set CLAUDE_CONFIG_DIR (agent_state, codex, command_names, cost, board_readme, init, flow, plan_epic, outcomes, review_yield, dash, skill, features, removed, roles), so under -P they could share ~/.claude. Each test file sets HOME or CLAUDE_CONFIG_DIR under its own mktemp root. The fixed sleeps (start_agent 3 s, deliver_prompt 5 s, watch_prs 60 s, send_goal and dash_watch 1 s, the codex stop and review loops 1 s; survey.json lists the lines) and MERGE_POLL and MERGE_CI_GRACE (bin/swarm.sh:3710-3714) multiply by SWARM_SLEEP_SCALE (default 1), which make test sets to 0.01; 0 would make watch_prs a busy loop. CI timing is after-release-checks'.

**Done when:**
- A grep in tests/sleep_scale_test.sh finds HOME or CLAUDE_CONFIG_DIR set under a mktemp root in every tests/*_test.sh.
- `make test` passes twice in a row, its output shows files running at the same time, a failing file makes it exit non-zero, and the PR body quotes its wall time; ci.yml's test job runs `make test`.
- tests/sleep_scale_test.sh: with SWARM_SLEEP_SCALE=0.01, a start_agent retry and a deliver_prompt wait each finish in under a second.

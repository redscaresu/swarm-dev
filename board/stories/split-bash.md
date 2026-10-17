---
kind: code
status: blocked
epic: swarm-sh-split
depends_on: [split-python]
touches: [bin/swarm.sh (whole file), bin/lib/*.sh (new), .github/workflows/ci.yml:shellcheck step, tests/*_test.sh:paths read, tests/command_names_test.sh, tests/removed_test.sh]
easy: false
estimate_lines: 4800
---

# Split bin/swarm.sh by command group into bin/lib/<group>.sh, no file over 1500 lines

A pure move, exempt from the size cap. Builds on split-python, whose bin/lib/*.py files it leaves alone. bin/swarm.sh keeps the usage header, die to json (bin/swarm.sh:1-307), the CONFIG_KEYS block (CFG defaults, CONFIG_KEYS, load_config, show_config), ROLE_GROUPS and policy, dispatch, READ_ONLY_COMMANDS, is_command, codex_review and main (is_command and usage read $0, :6741,6755). Groups: agents.sh (panes, start_agent, record_agent, record_event, story_text, deliver_prompt, stall, settle, wait_agent, tell_agent); reports.sh (finding log, lessons, cost, outcomes, flow, features, review-yield, findings); build.sh (rules, send_goal, story_brief, story_role, build_story, review_agent, touches_rows, conduct_brief, start_conductor); board.sh (fm, board, next_step, plannable_epic, dep_holds, costs_*, impossible_block, open_item, pr_stories, money_walk, unblock, finish_item, reset_story, drop_story, set_status, set_fm, get_fm, mark_review, reconcile); lifecycle.sh (board_pr, pull_board_repo and helpers, brief_trailers, close_agent, escalate_story, held_story, lead_block, tidy, init_project, lead_queue); merge.sh (ci_gate, merge_pr, merge_caller, release_check, watch_prs, stacked_*, status_report); dash.sh (dash*). The libs are sourced from ${SWARM_HOME}/bin/lib after the PROJECT_DIR/BOARD/STATE_DIR block (:200-211), so top-level assignments run in the same order as now: ROLE_GROUPS 269, MIN_CLAUDE 524, AGENTS_LOG 691, EVENTS_LOG and FINDING_*/LESSON_* 754-778, FEATURES_FILE 1506, PROMPT_TIMEOUT_MS..SETTLED 1664-1838, SET_FM_KEYS 3557, MERGE_* 3710, PULL_WHY 4325, CLOSE_CAUSE_WORDS/ESCALATED_* 6125-6205, LEAD_* 6517, CODEX_GRACE 6766. CI's shellcheck step covers bin/lib/*.sh (ci.yml:23), with source directives.

**Done when:**
- `wc -l bin/swarm.sh bin/lib/*` shows no file over 1500 lines.
- A whole-line check quoted in the PR body: the multiset of the base bin/swarm.sh's lines equals the multiset of lines across bin/swarm.sh and bin/lib/*.sh, apart from the added source lines and shellcheck directives.
- Every test that reads bin/swarm.sh's text (agent_state, command_names, config, epic, events, fail_lines, next, removed, roles, skill, dash_reexec) also reads bin/lib/*.sh, except where what it reads stays in swarm.sh, including the absence checks command_names_test.sh:11 and removed_test.sh:13,17; every tests/*_test.sh passes.
- shellcheck passes on bin/swarm.sh and bin/lib/*.sh, ci.yml's shellcheck step names bin/lib/*.sh, and `claude plugin validate .` passes.

---
kind: code
status: blocked
blocked_by: [drop-epic-prs, drop-verify, drop-unused-switches, backlog-conductor, flow-and-features]
epic: leaner-faster-swarm
depends_on: [drop-epic-prs, drop-verify, drop-unused-switches, backlog-conductor, flow-and-features]
touches: [bin/swarm.sh:CFG defaults, CONFIG_KEYS, load_config, conduct_brief, conduct_epic_mode, stop_rule, sign_rule, sign_rule_if_on, bump_rule, base_for, dash_base_ref, docs/method.md:§ Configuring a project pr_per and base_branches rows, tests/epic_test.sh:base_branches config lines, svc fixture, tests/events_test.sh:base_branches config line, tests/board_pr_test.sh:base_branches config lines, tests/config_test.sh:pr_per and base_branches checks, tests/removed_test.sh]
---

# The last of the old switches go: the pr_per and base_branches keys, conduct_epic_mode, and the definitions nothing reads any more

Waits on drop-epic-prs, drop-verify, drop-unused-switches, backlog-conductor and flow-and-features. Once they merge, nothing reads what this story deletes, and drop-epic-prs has deleted the pr_per = epic tests whose config lines name pr_per and base_branches. Check both projects' config again for pr_per and base_branches, and quote the greps in the PR. Delete: the defaults CFG_pr_per, CFG_sign_commits, CFG_finished and CFG_base_branches (bin/swarm.sh:138-144); pr_per and base_branches from CONFIG_KEYS (:154) and load_config (:182-183, :192-193); conduct_brief's pr_per branch and conduct_epic_mode (:2583-2636); stop_rule's pr_per case (:1873); sign_rule and sign_rule_if_on (:1876-1877); bump_rule and its comment (:1910-1917); base_branches in base_for (:265-283), which then always takes origin's default branch, its message 'set base_branches' included, and in dash_base_ref (:4056). Tests: drop every `base_branches = …` config line: tests/epic_test.sh's, whose svc fixture (:232-243) then takes dev as its base by setting the bare repo's HEAD to dev; tests/events_test.sh:198; tests/board_pr_test.sh:19 and :291. tests/config_test.sh's pr_per and base_branches checks. Add tests/removed_test.sh, which fails if `grep -nE 'pr_per|CFG_finished|sign_commits|sign_rule|review_bot|keep_panes|merge_admin|base_branches|bump_rule|epic_branch|conduct_epic_mode|decisions_report|export_report'` finds anything in bin/swarm.sh or tests/*.sh (itself excepted), or `grep -nw verify bin/swarm.sh` finds a line that is not a git --verify. docs/method.md: the pr_per and base_branches rows of § Configuring a project (:161, :170). bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- tests/removed_test.sh passes, and fails when any one of its tokens is put back in bin/swarm.sh (the PR shows one such run).
- tests/config_test.sh: a pr_per or a base_branches line fails with `unknown key`, and CONFIG_KEYS equals the keys in § Configuring a project's table.
- `swarm.sh base svc` prints origin's default branch, no file in tests/ has a base_branches line, and every existing brief check passes.
- The PR quotes the greps of both projects' config.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.

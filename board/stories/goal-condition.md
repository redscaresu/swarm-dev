---
kind: code
status: blocked
blocked_by: [method-config-table-test, wire-escalate-role, fable-on-call-release]
epic: goal-for-builders
depends_on: [method-config-table-test, wire-escalate-role, fable-on-call-release]
touches: [bin/swarm.sh:CFG_ defaults, CONFIG_KEYS, load_config (goal arm), bin/swarm.sh:story_brief (reply sentences), bin/swarm.sh:goal_condition (new), bin/swarm.sh:build_story (cap and goal file, beside require_claude), bin/swarm.sh:require_claude (minimum argument), tests/config_test.sh (config-file block; require_claude block), tests/epic_test.sh (Layout block; pr_per = epic block), docs/method.md (§ Configuring a project, the goal row), README.md (Requirements)]
---

# The goal setting (off by default): with goal = N, story writes each builder's goal condition beside its brief and refuses one it cannot send

New key goal: a CFG_goal=off default, CONFIG_KEYS, a load_config arm (off or ^[1-9][0-9]*$, before the unknown-key arm), and a method config-table row whose Default reads `off`. The two reply sentences in story_brief (epic mode: the pushed branch; story mode: the PR URL once CI is green) become one helper that story_brief, goal_condition and later the findings goal all read, so they cannot drift. A new goal_condition <slug> builds: the story's **Done when** block, its **From review (binding ...)** block when present, the mode's reply sentence, and `or stop after N more turns`. With goal on, build_story runs it beside require_trusted/require_claude, before base_for and any epic-branch push or add_epic_repo. Above GOAL_MAX_CHARS (4000) build_story dies naming the story and the length. Otherwise it writes the condition to .swarm/briefs/<slug>.goal.md beside the brief. Nothing sends it yet: goal-delivery does. With goal on, build_story asks require_claude for the version the spike named (2.1.269 unless it says otherwise) through a minimum argument. MIN_CLAUDE stays 2.1.145, so goal off needs no upgrade. CLAUDE_CODE_GOAL_CHECKIN_MINUTES is never set. With goal off nothing changes. Docs: the method table row and README Requirements (the version with goal on); humanizer over them.

**Done when:**
- tests/config_test.sh, the config-file block: `swarm.sh config goal` prints off with no config; goal = 10 is accepted; 0, -1, 1.5, two and on are refused naming file and line. method-config-table-test's check passes with the new row, and that row's Default column reads `off`, matching CFG_goal.
- tests/epic_test.sh, Layout and pr_per = epic blocks: with goal off, `story` writes no .goal.md and the brief holds the mode's reply sentence verbatim. With goal = 7, `story` writes .swarm/briefs/<slug>.goal.md holding the story's Done when lines, its From review lines, the same reply sentence the brief holds, and `or stop after 7 more turns`, in story mode and with pr_per = epic.
- With goal on, `story` on a story whose condition is over 4000 characters fails naming the slug. With pr_per = epic, afterwards no worktree, no story/<slug> branch and no epic/<epic> on the bare remote exist, and the epic file is unchanged.
- tests/config_test.sh, require_claude block: with goal = 5 and CLAUDE_STUB_VERSION one below the goal minimum, `story` fails naming that version; with goal off the same version passes.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From the spike (binding; overrides the scope above where they differ; report: .swarm/goal-spike.report.md, Claude Code 2.1.299; user chose form 1, bound 5, on 2026-10-14):**
- `goal = N` defaults the bound to 5 in the docs' example (the key still ships `off`). The condition ends `or stop after N more turns` and carries an escape clause: if the story cannot be done, reply `IMPOSSIBLE: <why>` and stop; that reply satisfies the condition.
- The cap is 4000 characters (the binary's own limit).

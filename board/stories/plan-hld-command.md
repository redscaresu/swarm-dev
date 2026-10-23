---
kind: code
status: blocked
epic: plan-hld
depends_on: [next-plan-hld, finish-hld, grants-hld-arm, lead-stop-plan-hld, plan-pr-grant]
needs: next-plan-hld's next_step plan-hld and hld arms and the removed_test.sh drop; finish-hld's swarm.sh finish <hld>; grants-hld-arm's swarm.sh grants <hld>; lead-stop-plan-hld's contract (tab plan-<hld>, branch board/plan-<hld>, .swarm/<hld>/critic.json); plan-pr-grant's attribution of the plan PR
touches: [commands/plan-hld.md (new), commands/swarm.md:plan-hld and hld steps after the plan-epic step, commands/hld.md:step 5 last sentence, templates/docs/hld/README.md:front matter block, board/hld/README.md:front matter block, bin/swarm.sh:ROLE_GROUPS and policy and finish and grants usage lines, bin/lib/agents.sh:codex_out_dir, tests/plan_hld_test.sh (new), tests/roles_test.sh, tests/review_test.sh, tests/command_names_test.sh]
estimate_lines: 220
easy: false
---

# /plan-hld decomposes an agreed HLD into epics with a swarm, and /swarm-dev:swarm runs it and finishes the HLD

Uses next-plan-hld's `plan-hld <hld>` and `hld <hld>` arms, finish-hld's `swarm.sh finish <hld>`, grants-hld-arm's `swarm.sh grants <hld>`, plan-pr-grant's attribution of the plan PR, and lead-stop-plan-hld's contract: tab `plan-$1`, board PR `plan-$1`, outputs in `.swarm/$1/`. Run the epic's **Checks before every stage**.

commands/plan-hld.md restores 45b2af1a^:commands/plan-hld.md (survey, decompose with role `hld-lead`, a skeptic per epic capped at five, codex, critic, the report order, Resuming), with these changes:
- The board_dir paragraph replaces hardcoded docs/. Agents start with `swarm.sh agent plan-$1 <name> ...` and are named survey-code and the rest as before, never after the HLD, because names truncate at 32 characters (bin/swarm.sh:383-389). Every agent writes `.swarm/$1/<name>.json`.
- Before the ask it runs `swarm.sh grants $1`. With `epics` listed, it writes the epics `status: active` and opens the board PR without asking, and says so in the report. Without it, it writes them `status: draft`, each agreed through /epic, and asks before board-pr open.
- Each epic carries `hld: $1` (no .md). In the same board PR (board-pr start/open `plan-$1`, one codex-review pass) the HLD gets `planned: <today>` in its front matter and its `## Epics` links each epic, and nothing else in the HLD changes, so plan-pr-grant can attribute it.
- If the board PR is already open, it reports the URL and stops: until it merges, main has no `planned:` and next would offer plan-hld again.
- Findings are logged with log-finding as plan-epic.md:104-106 does. After the merge it runs `swarm.sh board-pr done plan-$1` and `swarm.sh close plan-$1`; next then plans each epic. A board outside the repo is written in place.

hld-lead goes into ROLE_GROUPS' design group with policy `claude fable xhigh`. bin/lib/agents.sh codex_out_dir regains `plan-?*) .swarm/${1#plan-}` (lost in #293; without it codex starts read-only).

commands/swarm.md's step list gets two steps, inserted right after the `plan-epic <epic>` step and touching no other line (grants-reader edited the never-merge lines; epic-guard edits the draft-epic gate line):
- `plan-hld <hld>`: follow /plan-hld; the user approves unless `epics` is granted; the merge grant covers its board PR.
- `hld <hld>`: run `swarm.sh finish <hld>` and hand its PR to the user (the finish PR is always the user's under merge = human); once that PR merges or is closed, run `swarm.sh board-pr done finish-<hld>`, so an abandoned worktree never hides the HLD.

commands/hld.md step 5 adds that /swarm-dev:swarm plans the agreed HLD next. The HLD READMEs describe `planned:` in the prose under the front-matter block (set only by /plan-hld's board PR), never as a line in the fenced skeleton: commands/hld.md step 1 copies that skeleton, so a `planned:` line there would mark every new HLD as planned and offer it for deletion once agreed. bin/swarm.sh's finish and grants usage lines name an HLD. Run humanizer over the commands/ prose and the PR description, and say so in the PR.

**Done when:**
- tests/plan_hld_test.sh (one grep per rule, as tests/hld_command_test.sh does) fails if commands/plan-hld.md loses: three survey agents; one hld-lead; the skeptic cap of five; codex; critic; `swarm.sh agent plan-$1`; `.swarm/$1/`; `swarm.sh grants $1` before the ask; active under `epics` and draft otherwise; `hld: $1` on every epic; `planned:`; the `## Epics` link; board-pr plan-$1; codex-review; log-finding; `board-pr done plan-$1`; `swarm.sh close plan-$1`; the stop when the board PR is already open.
- tests/plan_hld_test.sh greps commands/swarm.md for a `plan-hld <hld>` step, an `hld <hld>` step naming `swarm.sh finish <hld>`, and `board-pr done finish-`.
- tests/roles_test.sh: hld-lead is in ROLE_GROUPS and policy, `swarm.sh policy hld-lead` prints `claude fable xhigh`, and commands/plan-hld.md reaches the role. The 'hld-lead is in neither' check (:62-64) is gone.
- tests/review_test.sh: `swarm.sh agent plan-h cx codex` starts codex with `-s workspace-write -C <project>/.swarm/h`.
- tests/command_names_test.sh requires commands/plan-hld.md; doc_check, skill_test and `claude plugin validate .` pass.
- tests/plan_hld_test.sh fails if the fenced skeleton in templates/docs/hld/README.md holds a `planned:` line.
- `make test` passes.

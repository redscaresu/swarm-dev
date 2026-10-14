---
kind: code
status: blocked
blocked_by: [close-takes-a-cause, goal-wait-no-nudge, goal-on-findings, conductor-give-up-rule]
epic: goal-for-builders
depends_on: [close-takes-a-cause, goal-wait-no-nudge, goal-on-findings, conductor-give-up-rule]
touches: [bin/swarm.sh:goal_rule (new), bin/swarm.sh:give_up_rule (goal-on wording), bin/swarm.sh:conduct_story_mode, bin/swarm.sh:conduct_epic_mode, commands/swarm.md (story arm), tests/epic_test.sh (conductor's-brief checks in the Layout and pr_per = epic blocks), README.md (§ When /swarm stops for you), docs/method.md (§ Building, the give-up paragraph)]
---

# With goal on, conductors and /swarm read why a builder stopped and close it with that cause; cleared-on-error stops the wave

A goal_rule heredoc beside auth_rule and give_up_rule, which conduct_story_mode and conduct_epic_mode include only when CFG_goal is not off. When `wait` returns idle for a builder short of its reply, the conductor reads the reply and the transcript (the session .jsonl for field 7 of the builder's .swarm/agents.tsv line) for the goal entry the spike quoted, never the pane, and acts on the cause. met: review as today; the closes after review or merge stay bare, which close-takes-a-cause allows. impossible: `swarm.sh close <slug> impossible`, then list the lead item. stalled or bound: `swarm.sh close <slug> <cause>`, and retry in a later wave. paused: one `swarm.sh tell <slug> resume <file>`; if it stops paused again, `close <slug> paused`. cleared-on-error, or a `story` that failed on a refused goal: `close <slug> cleared-on-error`, start nothing more in the wave, and list it for the user. give_up_rule's goal-on wording replaces 'idle with no PR after wait's nudges' with 'idle short of its reply: follow the goal rule'; its stall close becomes `close <slug> stalled`. With goal off it is unchanged. commands/swarm.md's story arm gets the same for the lead's one-offs. README § When /swarm stops for you gets a cleared-on-error row, and method § Building's give-up paragraph (added by conductor-give-up-rule) gets one sentence; humanizer over them.

**Done when:**
- tests/epic_test.sh, the conductor's-brief checks in the Layout and pr_per = epic blocks: with goal = 5, the story-mode and epic-mode briefs each name all six causes, `swarm.sh close <slug> impossible`, one `tell <slug> resume` for a pause followed by `close <slug> paused`, and that cleared-on-error stops the wave. Each check fails with goal_rule's call removed from that mode.
- With goal = 5, neither brief says 'after wait's nudges', and both say `close <slug> stalled`. With goal off, both briefs say 'after wait's nudges' as conductor-give-up-rule left them, and contain neither 'cleared-on-error' nor `close <slug> impossible`.
- `grep` finds the six causes and `close <slug> <cause>` in commands/swarm.md's story arm, and a cleared-on-error row in README § When /swarm stops for you.
- humanizer ran over the changed README/docs/commands prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From the spike (binding; overrides the scope above where they differ; report: .swarm/goal-spike.report.md, Claude Code 2.1.299; user chose form 1, bound 5, on 2026-10-14):**
- goal_rule tells the conductor how to read the cause as in close-takes-a-cause's spike note: the reply first (`IMPOSSIBLE:` or the story's reply), then the final `goal_status met:true` entry's `reason`.
- The judge's tokens are outside `swarm.sh cost`; the report for goal-on-for-infrafactory sums `goal_status.tokens` from met entries as a count, with no price.

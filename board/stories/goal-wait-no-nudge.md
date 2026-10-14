---
kind: code
status: blocked
blocked_by: [goal-delivery]
epic: goal-for-builders
depends_on: [goal-delivery]
touches: [bin/swarm.sh:wait_agent, tests/epic_test.sh (the wait block), docs/method.md (§ Building, the wait paragraph)]
---

# wait never nudges a builder that has a goal: it returns idle for the conductor to read the cause

In wait_agent, the nudge is skipped when CFG_goal is not off (a cheap first check) and goal_entry <name> 0 finds a goal entry in the builder's session. Such an idle builder short of its PR returns idle at once, with no prompt and no `nudge` line: the goal retries on its own, and the conductor reads why it stopped. A builder with no goal entry is nudged as today: one started with goal off, or one whose /goal was refused. With goal off nothing changes. goal-conductor-rule rewords give_up_rule's 'after wait's nudges' for goal on; this story does not touch it. Docs: one sentence in method § Building's wait paragraph (the one starting '`wait` returns when'); humanizer over it.

**Done when:**
- tests/epic_test.sh, the wait block: with goal = 5 and a session .jsonl holding a goal-set entry, the idle ready code story with no PR (the case nudged with goal off) makes wait return idle, with no `agent prompt` in herdr.log after the start and no `nudge` line in events.tsv.
- With goal = 5 and a session that has no goal entry, the same builder is nudged IDLE_NUDGES times, as with goal off.
- The existing goal-off nudge cases pass unchanged.
- The PR shows the new checks failing with the gate removed, and with the gate keyed on CFG_goal alone; humanizer ran over the changed docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From the spike (binding; overrides the scope above where they differ; report: .swarm/goal-spike.report.md, Claude Code 2.1.299; user chose form 1, bound 5, on 2026-10-14):**
- 'Has a goal' means the builder's .jsonl holds a `goal_status sentinel:true` and no later `goal_status met:true`. A met goal (met, bound or the IMPOSSIBLE escape) means the goal is over: wait behaves as goal off for that builder.

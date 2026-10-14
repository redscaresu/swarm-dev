---
kind: code
status: blocked
blocked_by: [goal-delivery]
epic: goal-for-builders
depends_on: [goal-delivery]
touches: [bin/swarm.sh:tell_agent, tests/next_test.sh (the tell block: its herdr stub, tellout, a session fixture), docs/method.md (§ Building, the **The goal.** paragraph)]
---

# With goal on, tell with findings sets a fresh goal with the same bound and confirms it set

In tell_agent, with goal on and kind findings, after the findings message is taken up, it sends a fresh /goal through goal-delivery's send-once mode, in the builder state the spike recorded. The condition is 'the findings in this message are addressed and' plus the mode's reply sentence from goal-condition's shared helper, plus `or stop after N more turns`. It confirms with goal_entry <name> <the tell's start time>: only a set entry newer than the tell counts, so the build-time one does not. A refused goal, or no new entry, fails the tell naming the slug. A nudge or resume tell sends no goal, and with goal off no tell does. `resume` stays counted apart from `nudge` (main's tell:<kind>, outcomes' tells_resume). Test: the tell block's herdr stub writes one delimited record per `agent prompt` to ${dir}/sent, and tellout sets CLAUDE_PROJECTS_DIR to a session fixture the stub appends the set entry to. Docs: one sentence in method § Building's **The goal.** paragraph; humanizer over it.

**Done when:**
- tests/next_test.sh, the tell block: with goal = 4 and the stub appending a set entry newer than the tell, `tell s1 findings f` exits 0 and ${dir}/sent holds two records: the findings, then a /goal holding 'the findings in this message are addressed', the story-mode reply sentence the brief uses and `or stop after 4 more turns`. With pr_per = epic, it holds the epic-mode sentence.
- The second record is sent in the builder state the spike recorded; the stub checks the status it reports at that prompt.
- With only a set entry older than the tell, `tell s1 findings f` fails naming s1; so does a stub that shows the goal on the pane with no new entry.
- `tell s1 nudge f` and `tell s1 resume f` write one record each; with goal off, `tell s1 findings f` writes one.
- tests/outcomes_test.sh still counts tell:resume apart from tell:nudge.
- The PR shows each new check failing with its code removed; humanizer ran over the changed docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From the spike (binding; overrides the scope above where they differ; report: .swarm/goal-spike.report.md, Claude Code 2.1.299; user chose form 1, bound 5, on 2026-10-14):**
- The fresh goal is form 1, sent after the findings turn is idle, confirmed by a `goal_status sentinel:true` newer than the tell (the build-time sentinel never counts).

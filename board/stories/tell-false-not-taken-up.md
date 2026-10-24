---
kind: code
status: ready
depends_on: []
touches: [bin/lib/agents.sh:prompt_settle and deliver_prompt, tests/tell_note_test.sh]
estimate_lines: 100
easy: false
---

# tell stops reporting a delivered brief as not taken up, and stops sending it twice

`tell` reported "the brief was not taken up: herdr sent it the brief twice, and herdr reads it idle with no turn finished since" for plan-hld-command at 07:52, 08:34 and 09:21 on 2026-10-24 (.swarm/events.tsv). Each time the builder acted on the findings and pushed a new head. So `deliver_prompt` (bin/lib/agents.sh, around :690) sent the same findings twice, and the event read as a failure. That failure also hid the round from the ladder (see findings-told-sent). Conductor reports since 0.25 list the same false "not taken up".

- Find why `prompt_settle` reads a builder that took the prompt as idle, with the same turn count, for all of its reads. Use the three events above and the builder's session log under ~/.claude/projects. Likely suspects: a builder with background shells running, or a turn that starts after the last read. Fix the reading, so that a brief taken up is reported `ok` and never sent a second time.
- If the evidence cannot settle it, then once herdr has sent the brief, do not send it again. Report "sent; herdr did not show the turn start" as a warning outcome. `findings_told` should count it, so match findings-told-sent's wording.

**Done when:**
- A test in tests/tell_note_test.sh, with a stubbed herdr that stays idle for the settle reads and then shows a finished turn, passes: `tell` sends the brief once and logs an outcome that is not "not taken up".
- The PR body names the cause found, with the session-log evidence.
- `make test` passes.

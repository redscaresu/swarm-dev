---
kind: code
status: ready
epic: delivery-liveness
depends_on: []
touches: [bin/lib/agents.sh:agent_stalled, tests/agent_liveness_test.sh:bg stall cases, docs/reference.md:the stall paragraph in Building, docs/reference.md:stall_minutes setting, docs/method.md:signs of life, bin/lib/dash.sh:stall pre-pass, tests/dash_stalls_test.sh:background task case]
estimate_lines: 50
easy: true
---

# A builder waiting on its own background task is not stalled

Goal 3, first half. agent_stalled (agents.sh:1350-1365) reads bg_running (agents.sh:1215) for the builder's agent name next to test_running (1358), after the age check and before the PR read. It returns not-stalled when bg_running is true. That one edit covers both callers (herdr_wait agents.sh:1427, settle 1496). bg_running reads the transcript, not the pane. No incident or field is added: the stall inputs belong to telemetry-writers. A background task counts as life only while it is younger than 3 x stall_minutes, as test_running's age cap does (bin/lib/agents.sh:1222-1225), since bg_running has no age cap (bin/lib/panes.py:81-111): a builder that left a server running in the background must still read as stalled. dash's stall pre-pass (bin/lib/dash.sh:731-737) reads the same signals, so dash and wait --stall agree. docs/reference.md's stall_minutes setting (:800) and docs/method.md's signs of life (:125) say a live background task now counts.

**Done when:**
- tests/agent_liveness_test.sh: a builder past stall_minutes with no commit, edit or test run, whose transcript shows a background task with no end, gets no `stalled:` from `wait --stall`, on the herdr_wait path and on the settle path.
- False case: the same builder with no background task (or one that has ended) gets `stalled: working <N> min ...` and exit 3.
- Deleting the bg_running line from agent_stalled turns the background-task case red (copy-aside proof).
- docs/reference.md's `wait --stall` paragraph in Building lists a live background task among the signs of life.
- A builder whose only sign of life is a background task older than 3 x stall_minutes reads as stalled; one younger reads as working.
- dash shows the same state as wait --stall for a builder with a live background task (tests/dash_stalls_test.sh).

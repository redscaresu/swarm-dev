---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [incident-slug-role, wait-timeout-activity, flow-incidents-causes]
needs: [incident-slug-role: the stalled incident with agent_fields (bin/lib/agents.sh:wait_agent), wait-timeout-activity: stall_reads (bin/lib/agents.sh) and its wait_agent edit, flow-incidents-causes: the stalled-input table and any-input-1 count in bin/lib/flow_incidents.py]
touches: [bin/lib/agents.sh:wait_agent (stalled incident inputs), bin/lib/agents.sh:agent_stalled (inputs out), bin/lib/lifecycle.sh:start_rung (escalate stalled event), tests/escalate_triggers_test.sh:stall input cases, docs/reference-logs.md:stalled sentence (Logs and outcomes), bin/lib/lifecycle.sh:ladder_step, bin/lib/lifecycle.sh:step_up]
estimate_lines: 200
easy: false
---

# stalled incidents and stalled step-ups log the bg, test and sign inputs

From incident-slug-role it uses the stalled incident with agent_fields; from wait-timeout-activity, stall_reads and its wait_agent edit; from flow-incidents-causes, flow incidents' stalled-input table, for the end-to-end case. The stalled incident (wait_agent, agents.sh:1637) carries bg= test= sign= as agent_stalled read them. agent_stalled stalls only when all three read false and runs inside $(...) (settle, agents.sh:1579; herdr_wait :1510), so on that path all three are 0 by construction: pass them out as read, never re-read after the verdict. The escalate stalled event (start_rung's escalate line, lifecycle.sh:888) carries them too: from the wait's check when wait_agent's ladder_step started it, and read fresh by stall_reads when `step-up <slug> stalled` ran from anywhere else, where a 1 can show. The docs say which path gives which, so Goal 3's bar is read knowing that.

flow incidents also counts stalled step-up events and flagged panes (HLD Goal 3), with a real false-stall path in the test, not only a hand-run step-up.

**Done when:**
- tests/escalate_triggers_test.sh: a stalled wait (agent_stalled stubbed to stall) writes a stalled incident and an escalate stalled line, each with bg=0 test=0 sign=0 in fields().
- A hand-run `step-up <slug> stalled` with a background task stubbed live writes the escalate line with bg=1.
- End to end: that bg=1 line's slug shows in flow incidents' stalled-input table and its any-input-1 count is 1.
- Copy-aside proof: dropping the fresh read on the hand-run path turns the bg=1 case red.
- docs/reference-logs.md's stalled sentence names the three inputs and which path writes each value.
- A test drives a false stall (a live background shell) through the wait's path to a step-up event, and flow incidents counts it with bg=1; a flagged pane counts too.

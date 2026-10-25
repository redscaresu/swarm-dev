---
status: active
hld: 2026-10-25-swarm-dev-0-28
stage: v0.28.0
depends_on: []
---

# Two false liveness readings are fixed

Two false liveness readings are fixed: a running test suite in an agent's pane is never read as a stall, for a builder or a conductor, and a brief left unsent in a pane's input box is sent once more as a nudge and then reaches the lead through no-agent-alert's marker family. HLD Goal 8, Design § Nothing sits unworked unseen (an unsent brief; a long test run is not a stall).

**Done when:**
- agent_stalled (bin/lib/agents.sh:1161-1175) and pane_quiet (agents.sh:1073-1081, which exempts only bg_running today) both count a scripts/test.sh or make test process in the pane's process tree as work, read through herdr pane process-info (bin/lib/longest_child.py, agents.sh:1146), never from the run marks; tests show no stall for a builder and for a conductor with a run going, and a stall for each without one.
- After a start or a tell, a pane herdr lists idle whose input box still shows `[Pasted text #N]` gets one resend as a submit of the text already in the box or as a nudge, never as a second findings tell (findings_told counts sent briefs, agents.sh:1677-1683, so a resent findings brief would count a round twice and from v0.30.0 step up at round 2); the check runs from wait --lead, one pane read per agent the list shows idle, after deliver_prompt has returned (agents.sh:760-763); tests cover an agent that took the brief (no resend, no marker) and one that did not.
- Still unsent after the resend, deliver_prompt writes `.swarm/briefs/<slug>.unsent` in no-agent-alert's marker format, and the lead line reads `unsent brief: <slug>, exit: swarm.sh close <slug> then resume`; a test with the marker.
- reference.md documents the resend, the marker and the stall rule; doc_check passes.

**Out of scope:**
Any change to scripts/test.sh or the run marks (test-speed's alone); the core no-agent rule and lead_queue (no-agent-alert); the review agent's own loop.

**Constraints:**
- A pane read goes through herdr (herdr agent read / pane process-info), never a bare herdr agent prompt; one read per idle agent, none in the 30 s poll's list pass.
- Signals must be true: the resend is tested against the false case (the 29 false 'not taken up' of 0.27, fixed by #464) as well as the real one.
- Order: this epic's resend story goes after no-agent-alert's core story (the resend pass runs in wait_lead, bin/lib/lifecycle.sh:1908, off the herdr list read that story adds), and this epic's unsent-marker story after no-agent-alert's marker story (it writes the format that story defines).
- tests/dash_stalls_test.sh (SERIAL), tests/agent_liveness_test.sh, tests/escalate_triggers_test.sh pin today's stall lines and are extended, not weakened; bin/lib/stall.py holds the age logic.
- bash 3.2, shellcheck, loose_match_test, make test; humanizer over docs prose.

**Areas:** bin/lib/agents.sh:agent_stalled, bin/lib/agents.sh:pane_quiet, bin/lib/agents.sh:deliver_prompt, bin/lib/longest_child.py, bin/lib/stall.py, bin/lib/lifecycle.sh:wait --lead resend pass, docs/reference.md:stall and unsent brief, tests/ (dash_stalls, agent_liveness, escalate_triggers, the resend test)

**Your part:**
None; the cut is the release story's.

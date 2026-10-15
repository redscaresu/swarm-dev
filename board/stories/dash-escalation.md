---
kind: code
status: ready
epic: dash-tells-the-truth
depends_on: []
touches: [bin/swarm.sh:dash_render (header, agent_cols, Recent events loop and ICON), tests/dash_test.sh (header regex :151 :235; new block after :397), docs/dash.md (header, agent rows, Recent)]
---

# The dash shows Fable on call, each escalated builder's ladder step, and escalation events

dash_render (python heredoc) only, no shell change: the inputs are already exported (DASH_POLICY, DASH_EVENTS, DASH_AGENTS_LOG; bin/swarm.sh:2914-2923). Header: after the version, `on call: <model>·<effort>` from the policy's `escalate` line (`on call: off` when escalate_after is 0) and `N escalations today` = ok `escalate` events whose local date is today (when() converts UTC); dropped with the version in the narrow layout (:3355-3366). Row: an agent whose agents.tsv role is `escalate` (rec[1], :3071-3099) shows its ladder step and escalation time from its slug's newest `escalate` event outcome `ok (attempt N)` (:1767), e.g. `attempt 3 · 14:02`. Recent: `escalate`, `dialog`, `escalated`, `reset` and `drop` lines get their own ICON kind and style (:3287-3290), with their time as today. Update the pinned header regex (tests/dash_test.sh:151, :235). Add the fixture lines in a new block after the stall checks (:397), so the earlier pinned counts stay.

**Done when:**
- tests/dash_test.sh: with fixture events (two ok `escalate` today, one yesterday, one failed) the header at 160 and 100 columns contains `on call: fable·xhigh` and `2 escalations today`; with escalate_after = 0 it says `on call: off`. An escalate-role agent with a pane and an `escalate <slug> ok (attempt 3)` line shows `attempt 3` and that line's HH:MM in its row. Each of the five event kinds shows in Recent with the new icon, and a `tell` line keeps `·`. The PR shows each check failing with its code removed. The epic's checks before every stage pass.

**From review (binding; overrides the scope above where they differ):**
- Add DASH_ESCALATE_AFTER="${CFG_escalate_after}" to dash's env block; dash_render cannot otherwise tell escalation is off (DASH_POLICY always carries the escalate row). Drop the 'no shell change' claim.
- At 100 columns the header has no room (budget 91): put `on call: …` and the count on the summary line below 140 columns and in the status bar at 140 and over; say whether a zero count shows. Done when checks those positions.
- 'Today' must not drift across midnight: the renderer takes its 'now' from an env override (e.g. DASH_NOW, epoch seconds) that the test fixes, and fixture lines are built relative to that fixed time; DASH_CLOCK only changes displayed text and TZ does not freeze time. A failed reset, drop or dialog line still shows ✗; add that check.

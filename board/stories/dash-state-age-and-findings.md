---
kind: code
status: blocked
blocked_by: [dash-escalation]
epic: dash-tells-the-truth
depends_on: [dash-escalation]
touches: [bin/swarm.sh:dash_render (agent row state, agent_cols, Recent events loop), tests/dash_test.sh (new block), docs/dash.md (agent rows, Recent)]
---

# Working builders show how long since their last sign of life, and Recent folds runs of log-finding lines into one row

Two small dash_render changes in one PR, since both edit the hot function. (1) Age: stall_age (bin/swarm.sh:456-471) is already called for every working builder with a story (:3092); keep its value on r and show it in the row for every working builder, not only past stall_minutes. Past the threshold it stays `stalled Nm` with its look mark and needs-you sentence, unchanged. An agent with no story slug (a conductor) keeps the since-start age (:3170-3173). (2) Grouping: in the events loop (:3287-3289), a run of consecutive ok `log-finding` / `log-finding:declined` lines on one PR (target `<kind> <PR URL>`, :3934-3936) becomes one row: `N findings declined on #PR`, `N findings logged on #PR`, or `N findings on #PR (K declined)` when mixed, at the newest line's time. A single line stays as today; a failed line stays its own ✗ row. findings.tsv's fold (:3280-3285) is unchanged. Append new checks after dash-escalation's block.

**Done when:**
- tests/dash_test.sh: a working builder whose worktree's last commit is 12 min old shows `12m` in its row at 160 and 100 columns; s-three still shows `stalled 1(19|20|21)m` and the same needs-you sentence; a conductor row keeps its since-start age. Eight consecutive `log-finding:declined` lines on pull/133 give exactly one Recent row containing `8 findings declined on #133`; a `tell` line between two groups splits them into two rows; a lone `log-finding` line reads as before. The PR shows each check failing with its code removed. The epic's checks before every stage pass.

**From review (binding; overrides the scope above where they differ):**
- Recent drops ok `log-finding` (fixed) event lines: findings.tsv's fold already shows each fix. Grouping applies to ok `log-finding:declined` runs on one PR (`N findings declined on #PR`); a failed line stays its own ✗ row. Done when: a fix logged through `log-finding` (written to both findings.tsv and events.tsv) appears in Recent exactly once; a lone declined line reads as before.
- Age format is the state age right after the state (`working 12m`), with the since-start column kept after it at 160; the fixture builder's start is not 12 min ago, so `12m` can only come from the state age.
- Every working agent gets the state age and the stall_minutes mark: conductors, planners and escalate rows use their own events.tsv lines as signs, falling back to since-start when there are none. Done when covers a working conductor below and above the limit.
- docs/method.md's stall_minutes row (:133) is updated to match where a stalled agent now shows.

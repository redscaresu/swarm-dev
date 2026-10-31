---
status: draft
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.31.0
depends_on: []
---

# board-loose-ends

HLD Goal 16 and Rollout § Readings (v0.31.0): every later, parked or orphaned lead story is shipped, re-homed or closed with a reason; release-v0-31-0 closes itself; the checkpoint lead story reads Goals 1 to 9 against their bars from flow; a retro lead story reads Goals 1 to 14 at retro-v0.31.0, since retro-report's own story reads the 0.28 readings only (contradiction 36).

**Done when:**
- stage: v0.31.0
- Checkpoint (kind: lead): after the first 20 story merges of v0.31.0 or seven days, whichever first, the lead runs flow once (after gh api rate_limit) and records Goals 1 to 9 against their features.tsv bars in board/retros/v0.31.0-checkpoint.md, each from the section its row names (time_in_state review_wait, review_loops totals, tell_refusals, incidents stalled inputs, start_failures, incidents lead-hand over throughput merged, lead_queue p90_min, merges holds by kind, and rules-file's and ladder-cost's own rows); a goal off its bar files a story in the stage; a feature that made things worse (more red CI under review_verify = ci; deferred_proved_real over its bar) is turned back by its config line and listed for the retro.
- Retro reading (kind: lead, depends_on retro-report's retro-v0.31.0 story once filed): at the retro the lead records Goals 1 to 14 against their bars, the v0.30.0 build's flow as the second baseline, and the `swarm.sh dropped-lines` rerun over every story PR merged since v0.30.0 (Goal 8's true reading), in a second section of board/retros/v0.31.0-checkpoint.md and, by board-pr, in retro-v0.31.0's story; the HLD says the retro reads everything (HLD:589-590) and this is the story that does it.
- ppid-check-after-review (ready, epic: test-speed, gone) is re-homed here and run (v0.28.0 is installed, so it can), or closed with a reason.
- sonnet-share-on (ready, no epic) has a You: step: the user decides run or close (the experiment is theirs).
- unsent-resend-real-pane (blocked on unsent-brief-resend, not on the board) is closed with a reason, or re-homed with the test it still needs named.
- release-v0-31-0 gets a Done when that closes the story and a step that records the checkpoint's and the retro's readings; its step 4 agrees with retro-report's retro over v0.27.2..v0.31.0 running before the cut.
- docs/lead-by-hand.md has no #696 entry (lines 91-96 today): release-v0-30-0's docs step removes it once rules-file-briefs has merged (lead_now); if it is still there when this epic plans, a docs story here removes it (critic: the entry had no owner).
- codex-agent-name is recorded as absorbed by lead-woken's #691 story (its file deleted there); the seven kind: lead standing steps (config-switch-ons, flow-after-the-epic, merge-agent-on, merge-queue-on, merge-admin-on-for-infrafactory, merge-agent-for-infrafactory, review-yield-tuning) are named as retro-v0.31.0's to close or re-date, not this epic's.
- The retro reading of Goals 1 to 14 is written inside the retro-v0.31.0 lead story (its own step), not by a story that depends on it, since that story leaves the board when it is done.
- `wait --lead` re-reads the board after each merge, never exits without printing a line, and checks a line still holds before printing it; a test drives each failure the v0.30.0 build saw (silent exit, a stale line, a removed story file). Built first in v0.31.0 (HLD § v0.31.0 additions).
- `wait --lead` prints a line when an epic's plan swarm has finished or one of its agents never wrote its output (#762).
- `flow`'s predictions section scores the planner: `flow` builds `.swarm/dataset.jsonl` itself, or prints the command that does.

**Out of scope:**
The retro itself (retro-report); the seven standing lead steps; new features; release-v0-30-0 (the lead edits it now, lead_now).

**Constraints:**
- stage: v0.31.0. Depends on no epic. Mostly kind: lead stories with You: steps; board edits go by board-pr (a plan PR cannot touch stories, commands/plan-hld.md:156-168).
- The checkpoint's and the retro's numbers come from the flow sections the features rows name, no pane read (HLD Goal 6's bar); a row whose section is missing is a finding against telemetry-writers, not a pane read.
- retro-v0.31.0 (retro-report) confirms the later stories' fate; this epic decides it: no double entry (board/epics/retro-report.md:15). The retro-reading story depends_on retro-v0.31.0 by slug once retro-report files it.

**Areas:** board/stories/ppid-check-after-review.md:epic, board/stories/sonnet-share-on.md, board/stories/unsent-resend-real-pane.md, board/stories/release-v0-31-0.md, board/stories/codex-agent-name.md (deleted by lead-woken), board/retros/v0.31.0-checkpoint.md (new), board/stories/<checkpoint lead story> (new), board/stories/<retro-reading lead story> (new), docs/lead-by-hand.md:#696 (if still there)

**Your part:**
- Decide sonnet-share-on: run or close.
- Confirm each orphan's close reason when the plan reports it.
- At the checkpoint: read the record and say which features, if any, to turn back. At the retro: read Goals 1 to 14 as recorded and decide the deferred-findings and review_verify questions.

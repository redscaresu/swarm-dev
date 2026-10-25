---
status: active
hld: 2026-10-25-swarm-dev-0-28
stage: v0.28.0
depends_on: []
---

# No story sits unworked unseen

No story sits unworked unseen: a story whose build has started and that has no live agent of any role and no tell pending reaches the lead through wait --lead, next and status, each line naming its exit; a failed step-up and a review agent that never started are cases of it, read from files inside the poll; flow's lead_queue measures the minutes from the real event to the wake. HLD Goal 8, Design § Nothing sits unworked unseen (the rule, the failed step-up, the review agent that never started, every alert names its exit).

**Done when:**
- The population is defined in code and docs: a story with a build record (.swarm state), status ready or review, not held, not escalated, not kind: lead, not blocked, and not already in lead_queue's merge: or kept: lines; a live agent is a pane herdr lists for any role tied to the slug (builder, review-<slug>, or the conductor while it waits on wait-pr for that PR); a tell pending is an unanswered tell line in events.tsv. lead_queue (bin/lib/lifecycle.sh:1793-1859) emits `no-agent: <slug>, exit: swarm.sh resume <slug>, or hold with a reason` for it; wait --lead returns on it; next and status name it first (bin/lib/board.sh:next_step, bin/lib/merge.sh:1814 status_report and bin/lib/status_report.py).
- False cases, each a test that stays silent: a ready story not yet started (queued on capacity, a clash or a depends_on); the CI window after a push with the builder idle and the review agent closed; the 2026-10-25 `close review-config-keys-back` case between review rounds; a story in review waiting on the user; a held story; a kind: lead story. True cases, each a test that fires: a builder pane gone with the story ready; a review agent gone with its PR open and no round under way.
- Marker family: lead_queue reads `.swarm/briefs/<slug>.<kind>` markers inside the poll with no herdr or gh call; a `.step-up` marker left by a failed step-up (lifecycle.sh:622, 791) reaches the lead within one poll with the exit `step-up --resume <slug>`, not in the conductor's final report (bin/lib/build.sh:954-955 rewritten); the format is documented so liveness-signals' `.unsent` marker rides on it; a test with a marker and no builder.
- A PR in review with no live review agent and no round under way reaches wait --lead with the exit `swarm.sh review-agent <slug> <pr>` or the fallback reviewer, from files only (the agents list and .swarm/reviews/<slug>.md, not merge.sh:1478-1490's gh-backed queued_line, which stays for conductors); a test for the real case and for a round under way.
- flow's lead_queue reports minutes from a real event (the close line, the failed start, the marker's mtime, or the first poll that saw the pane gone, written as its own ENTER line kind in bin/lib/flow_lead_queue.py:12-14, never by the same poll that writes lead-woken) to the `lead-woken` line, which now carries the line kind (lifecycle.sh:1857); it also counts alerts fired while the builder was working (a wake whose slug had a live builder at the time), which must be 0 on the fixture; dash shows the same number (swarm.sh dash --check exits 0); docs/features.tsv has the row with metric `flow lead_queue: no-agent minutes, median`, bar 2 polls (60 s), and the 0.27 baseline (3.5 h step-up gap, 3h42m unsent brief, Appendix A).
- small-fixes-027's lead_queue keep rule and the liveness read that took a review agent's start as 'unclear' (board/stories/small-fixes-027.md:13-16) are fixed inside the core rule's story, each with a test that fails before the fix; fixes-027 strikes those two items when it adopts the file, citing this epic's merged PR.
- reference.md documents every new line kind and its exit; doc_check passes.
- commands/swarm.md's `wait --lead` handler acts on each new line this epic adds (`no-agent:` and the markers), running the exit the line names, and a test fails if `wait --lead` can print a line kind the handler does not list.

**Out of scope:**
A hook-based detector (the work is swarm.sh polling, hooks/ unchanged); the review agent owning its PR (review-loop re-runs this epic's tests under the new owner); the stall misread and the unsent brief (liveness-signals); a usage reading.

**Constraints:**
- Signals must be true: every new alert is tested against the false case as well as the real one (the 29 false 'not taken up' of 0.27).
- Every alert names its exit (method.md § Who does what).
- Budget: lead_queue runs inside the 30 s LEAD_POLL with one `herdr agent list` read per poll and file reads; no gh call and no per-pane read in the poll (the per-pane read is liveness-signals' and runs only for an agent the list shows idle).
- tests/wait_lead_test.sh, tests/lead_queue_wait_test.sh, tests/dash_check_test.sh (SLOW), tests/agent_liveness_test.sh, tests/escalate_triggers_test.sh pin today's lines and are extended, not weakened.
- Story order: the core rule with next and status first; the marker, never-started and small-fixes items depend on it; the flow, dash and docs story last. The next story names stage-gating's next story in depends_on (both edit next_step).
- Touch docs/features.tsv as `docs/features.tsv:no-agent row`; bash 3.2, shellcheck, loose_match_test, make test; humanizer over docs prose.
- Order: liveness-signals' resend story goes after this epic's core story (the resend pass runs in wait_lead, bin/lib/lifecycle.sh:1908, off the herdr list read the core story adds), and its unsent-marker story after this epic's marker story.

**Areas:** bin/lib/lifecycle.sh:lead_queue and lead_wake, bin/lib/board.sh:next_step no-agent line, bin/lib/merge.sh:status_report, bin/lib/status_report.py, bin/lib/flow_lead_queue.py, bin/lib/build.sh:conduct_brief step-up line, bin/lib/dash_render.py:lead queue rows, docs/reference.md:lead queue lines, docs/features.tsv:no-agent row, tests/ (wait_lead, lead_queue_wait, dash_check, agent_liveness)

**Your part:**
The first v0.28.0 build also finds out whether a review agent starts under 0.27.2 (Rollout § This machine): if none does, the lead files it as the first real case for this epic. No other human step; the cut is the release story's.

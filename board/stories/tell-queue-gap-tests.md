---
kind: code
status: ready
epic: deferred-700
depends_on: []
touches: [tests/tell_queue_test.sh:header comment (:25-35), tests/tell_queue_test.sh:new cases (step-up take, requeue lock, TELL_PANE pin)]
estimate_lines: 220
easy: false
---

# Tests for three untested tell-queue paths

#700 items 5-7 (#626). Tests only; no change to bin/. tests/tell_queue_test.sh (header :25-35 lists what is covered). (5) A step-up or top-rung hold that does take queued findings (tell_agent's ladder_step/top_rung_hold, agents.sh:2170-2190, and tell_queue_pass); only the lock-held case is covered (:32-33). (6) tell_requeue's lock (agents.sh:2625-2631, note_lock :2027): with the lock held it puts the tell back without it (mv -n), callers :2497, :2568, :2577, :2590. (7) The TELL_PANE pin: a queued delivery goes to the pane the queue checked (agents.sh:2108-2110, :2198-2205, used in tell_deliver :2761 and deliver_prompt :1051); the pane-closed cases at :305-320 hit the die at :2140, not the pin. Keep new cases clear of :236-246, which flaky-fixed-sleeps (flaky-tests epic) edits. Prove each case fails by breaking the code it guards on a worktree copy, and say in the PR where each was broken.

**Done when:**
- tests/tell_queue_test.sh has a case where a step-up or top-rung hold takes queued findings, and it goes red when that path drops the queue (shown on a worktree copy)
- A case holds tell_requeue's lock and checks the tell is put back, not lost or doubled; it goes red with the lock check removed (worktree copy)
- A case checks a queued delivery goes to the pane the queue checked, not a new pane holding the name; it goes red with the pin removed before tell_deliver passes the pane as its third argument (agents.sh:2761) (worktree copy)
- The header comment lists the three new cases; scripts/select-tests.sh --run passes
- The requeue lock cases also check the lock is taken on an uncontended requeue and that another caller's held lock is left as it was; each goes red under its own mutation.

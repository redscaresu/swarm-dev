---
status: active
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.31.0
depends_on: [reference-split]
---

# deferred-700

HLD Goal 14 (v0.31.0): every deferred finding in #700 ends as a story or a reasoned drop, listed in the epic file before any story is filed. #700 names seven entries; two of them point at their PRs, which hold more, so the list is thirteen items.

**Done when:**
- stage: v0.31.0
- The epic file lists each item with story or drop and the reason: (1) #682 round 2: a several-PR story put in review by hand counts as review-agent work; (2) #682 round 2: lead_held misses a ready-reopened dependency; (3) #673 round 3: pane_where's record-name fallback reads like a real tab label; (4) #618: prompt_lines poll cost; (5) #626: a step-up or top-rung hold that takes queued findings has no test; (6) #626: the lock in tell_requeue (a race) has no test; (7) #626: pinning a queued delivery to the pane it checked (TELL_PANE) has no test; (8) #626: the broad 'could not be read' match in lifecycle.sh's resend pass and flow's round count, left for the lead; (9) #630: a gh child outliving the frame when python misses its 1 s margin; (10) #630: the skip file left when dash dies mid-frame; (11) #630: dash_deadline as a third copy of the wrappers; (12) #645: lead-agents workspace pane order, lock comment and message; (13) #654: epic-guard-renames' delete-and-re-add bypass.
- Every story filed from the list merges or is dropped in the file with its reason; #700 closes with the list; docs/lead-by-hand.md has no #700 entry to remove (it has none today; the HLD's '#700 entry' is the issue, not a lead-by-hand step).
- The user has read the list before any story is filed (the epic is the control under the stories grant, HLD:520-521).

**Out of scope:**
Changing tell delivery for the background-shell case (the checkpoint's call, with data, HLD:372-374); findings the v0.31.0 build raises (the next retro); #700's issues #685 to #699 (their own epics); the deferred findings review-rounds-end's cap logs (next's idle lines offer those).

**Constraints:**
- stage: v0.31.0. depends_on reference-split. Items 5 to 8 edit agents.sh tell code after delivery-liveness and telemetry-writers merged (v0.30.0), so no two epics edit tell_agent at once; items 9 to 11 edit dash readers after telemetry-readers' helper.
- Item 2 (lead_held) overlaps lead-woken's stuck: line and reported line: read what lead-woken shipped before filing it.
- A drop carries a reason the retro can read; no item is dropped for size alone. Items 5 to 7 are missing tests, not behaviour: a story for them adds tests only.

**Areas:** bin/lib/lifecycle.sh:lead_held, bin/lib/lifecycle.sh:prompt_lines, bin/lib/lifecycle.sh:resend pass match, bin/lib/lifecycle.sh:lead-agents workspace, bin/lib/agents.sh:tell_requeue, bin/lib/agents.sh:tell_queue_send (TELL_PANE), bin/lib/agents.sh:pane_where, bin/lib/dash.sh:dash_deadline, bin/lib/dash_slow.py, bin/lib/board.sh:epic_guard renames, bin/lib/flow_review_loops.py:round count match, tests/tell_queue_test.sh, tests/dash_time_limit_test.sh, tests/board_pr_test.sh:epic guard cases, tests/merge_rules_test.sh:epic guard cases, tests/wait_lead_test.sh, tests/stacked_status_test.sh, tests/status_time_limit_test.sh

**The list (read by the user 2026-11-01: no strikes):**
1. #682: a story in review with several PRs counts as review-agent work. Story agent-work-several-prs.
2. #682: lead_held misses a reopened ready dependency. Story agent-work-reopened-dep.
3. #673: pane_where's record-name fallback reads like a herdr tab label. Story pane-where-unlabelled-tab.
4. #618 prompt_lines poll cost: (b) an extra `ps -A -ww` per poll and (c) the candidate python's own session-log glob, story prompt-poll-one-ps; (d) key a stop on the newest own-work entry and (e) keep the old key while a running wait hides an api-error, story prompt-stop-key; (a) skip prompt_wanted while a conductor sits idle: drop, because an idle box is where a dialog or manual mode shows (#618 round 1, finding 1).
5. to 7. #626 test gaps (a step-up or top-rung hold taking queued findings, tell_requeue's lock, the TELL_PANE pin). Story tell-queue-gap-tests, tests only.
8. #626 broad 'could not be read' match. Story brief-unread-exact-match.
9. and 10. #630 gh child outliving a cut-short frame, and the skip file left behind (dash, status and next). Story dash-frame-leaves-nothing.
11. #630 dash_deadline as a third copy of the read wrappers. Story report-read-wrappers.
12. #645 lead-agents workspace: (b) the kept pane protects only while open and (c) a project pane made after an outside pane counts, story lead-agents-pane-order; (a) an old conductor of an epic named lead-agents: drop, because build.sh refuses every such start since #645 and no epic here has that name; #700's 'lock comment and message' were fixed on #645's next head.
13. #654 delete-and-re-add bypass of the epic guard. Story epic-guard-deleted-agreed.

**Your part:**
- Read the thirteen-item list in the epic file when the plan PR opens; strike any item you want dropped.

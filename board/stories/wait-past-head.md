---
kind: code
status: ready
epic: review-follows-head
depends_on: []
touches: [bin/lib/agents.sh:settle (per-slice head check), bin/lib/agents.sh:wait_agent (passes the head check on), bin/lib/lifecycle.sh:wait_command (--past flag and its refusals), bin/swarm.sh:wait usage line, docs/reference-building.md:wait paragraph after the swarm.sh wait code block, tests/wait_past_test.sh (new)]
estimate_lines: 230
easy: false
---

# swarm.sh wait --past <sha> <slug> also ends when the builder's push moves the PR past <sha>

Add --past <sha> to a builder's swarm.sh wait (wait_command, bin/lib/lifecycle.sh:5391-5419). It ends every way wait --stall ends today, and also, printing `pushed <new sha>` and exiting 0, on the first poll (settle's STALL_POLL_MS slice, bin/lib/agents.sh:1575,1690-1730) at which three things hold: the story's worktree HEAD is a commit other than <sha>; the worktree is clean (git status --porcelain prints nothing, as review_at_head requires, bin/lib/build.sh:911-929); and the PR's head is that commit (pushed, not just committed). Read the worktree with git on each poll. Read the PR's head with `gh pr view --json headRefOid` (as review_at_head does) only on a poll where the worktree has moved, so a quiet poll costs no GitHub API call (reliable-runs counts the agents' REST calls, HLD:503-505). Put the check in settle's loop (or wait_agent's, bin/lib/agents.sh:1763), so the stall, stuck, API-error resume, usage-limit and nudge handling stay as they are. A herdr-only agent (settle's herdr_wait path, agents.sh:1694-1695, used when no Claude session is recorded) gets the same check, on its first read and its last slice too. Refuse, waiting on nothing: a <sha> that is not 40 hex characters; --past on a conductor, a review agent, --until-report or --lead; a name with no story file on the board or no worktree (worktree_for). No setting. Update the wait usage line (bin/swarm.sh:7) and the wait paragraph after the `swarm.sh wait <slug>` code block (docs/reference-building.md:418-440). The test is a new tests/wait_past_test.sh with herdr and claude stubs, as in tests/review_agent_test.sh:14-60 (claude_stub.sh, SWARM_STALL_POLL_MS=200), and a gh stub whose PR head is a file and which logs its calls. Why: #765's review agent waited 30 minutes on a builder whose fix was already pushed and green (.swarm/events.tsv 2026-10-30T21:06:02Z). Scope of the cause: this fixes a reviewer whose wait read the builder as busy after the fix was pushed. events.tsv has no wait-timeout, stalled or stuck line near #758 or #765, so that cause is not proved; if a reviewer still waits on a finished builder once this ships, the other cause (the reviewer missing its own wait's exit) is review-follows-live-check's to report. The stall probes' own `gh pr view --json updatedAt` reads (agents.sh:1480) stay as they are: the no-extra-call promise covers only the new headRefOid read.

**Done when:**
- tests/wait_past_test.sh: the builder's Claude session stays busy and herdr says working. A commit in the story's worktree that the gh stub's PR head then names ends `wait --stall --past <old sha> <slug>` with `pushed <new sha>` and exit 0, on the first poll after the push, with a timeout of about two slices (poll 200 ms, timeout 450 ms). With the head check broken in a copy of the worktree, the same case times out with exit 1; the PR pastes that FAIL line.
- A push made before the wait starts (the builder already finished) ends it on its first read with `pushed <sha>`.
- A commit the PR's head does not name yet (not pushed) does not end the wait, and nor does a worktree with uncommitted changes: each case times out with exit 1, a check each.
- The same busy-builder case with no recorded Claude session (the herdr-only path) ends with `pushed <sha>` on the first poll after the push.
- With no new commit, the builder's session going idle ends the wait with `idle` and exit 0, as plain wait --stall does.
- The gh stub's log has no `headRefOid` read from polls where the worktree was still at <sha>.
- --past with a short sha, on conduct-<epic>, on review-<slug>, and on a name with no story worktree each refuses with a non-zero exit and a line naming the form, and waits on nothing.
- tests/doc_check_test.sh passes with --past in the wait usage line and in docs/reference-building.md.
- --past with --lead and with --until-report each refuse, and neither wait path starts; a check each.

---
kind: code
status: blocked
epic: merge-holds
depends_on: [wait-pr-expected-workflows]
needs: [wait-pr-expected-workflows: its changes to wait_pr's head read and check call in bin/lib/merge.sh, on which the --head re-read builds]
touches: [bin/lib/merge.sh:wait_pr, bin/lib/build.sh:wait_pr_rule, bin/lib/build.sh:green_rule wait line, bin/swarm.sh:wait-pr usage line, commands/swarm.md:stage arm wait-pr lines, commands/swarm.md:release arm wait-pr line, docs/reference.md:wait-pr row, AGENTS.md:wait-pr bullet, tests/wait_pr_new_head_test.sh (new), tests/epic_briefs_test.sh:wait-pr lines, tests/no_agent_test.sh:wait-pr --head case, tests/next_test.sh:wait-pr lines]
estimate_lines: 240
easy: false
---

# After a push, wait-pr waits on the pushed head when the caller names it

Uses wait-pr-expected-workflows' wait_pr head read (bin/lib/merge.sh:wait_pr), which now also reads changedFiles. Cause 1 of HLD Appendix C (board/hld/2026-10-25-swarm-dev-0-28.md:868-871): wait_pr reads the head once (its header at merge.sh:965: 'a later push is not followed'). If the first read after a push returns the old head, wait-pr exits 0 on the old head's green.
- Reproduce first, on main's code, with a gh stub whose first pr view returns the old, green head. Quote the run and its exit in the PR body.
- If cause 1 reproduces, add `wait-pr --head <sha>` (a full SHA or a hex prefix of at least 7). It reads the PR again each poll until headRefOid starts with <sha>, then waits on that head's checks. If the head is still another sha after WAIT_PR_GRACE, it exits 2 naming both.
- Without --head, wait-pr waits on whatever head GitHub reports at its first read. Right after a push that can be the old head. reference.md and AGENTS.md say so.
- Every instruction where an agent waits right after its own push passes --head:
  - the builder brief (wait_pr_rule, bin/lib/build.sh:24-30, used at :424): `--head "$(git rev-parse HEAD)"` in its worktree;
  - commands/swarm.md's stage arm (:330, :350) and release arm (:442), where the lead pushed the board or release PR itself: the head of the worktree that pushed it.
- The conductor waits from the main checkout (green_rule, build.sh:989), where `git rev-parse HEAD` names main. So wait_pr_rule takes the head as an argument. The conductor passes the PR's head: the sha `swarm.sh watch` printed for it (`checks finished on <sha>`, merge.sh:watch_prs).
- no_agent_busy (lifecycle.sh:2239-2247) must still count a `wait-pr --head <sha> <url>` process as answering for its story.
- User examples use the pinned form: swarm.sh's wait-pr usage line, reference.md's wait-pr row (:2374) and AGENTS.md's wait-pr bullet (:74). This is the one story in the epic that touches AGENTS.md.
- If cause 1 does not reproduce, add no flag and change no brief. Keep the test, which pins that wait-pr follows the new head, and record the run in the story file and the PR. The lead closes it.
- Order across epics: review-loop's owner-waits-green also edits merge.sh:wait_pr, and conductor-hands-off's conduct-brief-hands-off and less-noise's no-nudge-to-busy edit build.sh:green_rule. If any of them is open alongside this one, this merges first: it adds one argument and one clause.

**Done when:**
- tests/wait_pr_new_head_test.sh (new): the stub's first pr view gives head H0 (green), later views give H1 (pending, then green). The PR body quotes this case's result on main's code, and the story is closed or built according to it.
- When cause 1 reproduced, the same file shows: `wait-pr --head H1` prints `head H1`, prints pending, and exits 0 only once H1 is green, with check reads of H1 only. A prefix of 7 works the same. A head that never appears within SWARM_WAIT_PR_GRACE exits 2 naming the PR's head and the wanted one. `--head xyz` is a usage error with exit 2.
- When cause 1 reproduced: tests/epic_briefs_test.sh shows the builder brief's wait line carrying `--head "$(git rev-parse HEAD)"`, and the conductor brief's wait line carrying the watch-printed head, with no `git rev-parse` in it.
- When cause 1 reproduced: tests/no_agent_test.sh shows a running `swarm.sh wait-pr --head <sha> <url>` silences the story's no-agent line, as the unpinned form does. tests/next_test.sh passes.
- When cause 1 did not reproduce: the test pins that wait-pr waits on H1 once the PR reports it, and no brief or doc changes.
- tests/wait_pr_test.sh and tests/wait_pr_expected_test.sh pass unchanged.
- swarm.sh's wait-pr usage line, reference.md's wait-pr row, AGENTS.md's wait-pr bullet and commands/swarm.md's stage and release arms show the pinned form and say what the unpinned form does (only when cause 1 reproduced).

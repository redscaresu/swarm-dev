---
kind: lead
status: ready
epic: board-loose-ends
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# Lead: the orphaned and later stories' fates in one board PR, and release-v0-31-0 closes itself

1. Report each fate below to the user with its reason. **You:** confirm each close reason, and decide sonnet-share-on: run or close. 2. After the answers, the lead opens one board PR (swarm.sh board-pr; a plan PR cannot change stories). (a) ppid-check-after-review: re-home it. Set `epic: board-loose-ends` and drop `after: test-speed` (no test-speed epic is on the board). Its Done when quotes a release-v0.29.0 item that does not exist (release-v0-29-0.md:10-17); replace that with 'recorded in the PR that finishes it'. The lead then runs it after the next codex review, by its own steps. A one-off `ps` on 2026-11-01 found 0 PPID-1 test processes; that is not the story's check. (b) sonnet-share-on, if run: `epic: board-loose-ends` and `depends_on: []` (sonnet-share merged in #79). If closed: delete it, and set sonnet_share back to 0 in .claude/swarm/config in its own PR (a protected path, so it holds for the user). Facts for the user: sonnet_share = 4 is set. .swarm/agents.tsv has 5 code-sonnet builds out of 189 code builds, the last on 2026-10-28. escalate_ladder = sonnet,opus,fable is now on, so ladder steps mix into the comparison the story meant to keep apart (sonnet-share-on.md:11). (c) unsent-resend-real-pane: close it. Its blocker merged in #548 (v0.28.0), and the resend pass runs on every poll (lifecycle.sh:4252). events.tsv has no `unsent brief` lead-woken line and no incident about a resend since, so the check guards a case that has not come up. If the user keeps it, re-home it with `depends_on: []` and name the test it needs: a real idle pane with a pasted, unsubmitted brief. (d) reference-split-lead-steps: finish it. Its step is met (retro-gate, retro-report and handover-usage are active on main), and its epic shipped in v0.30.0. (e) release-v0-29-0: finish it if it is still on the board (stale since the v0.29.0 tag; the HLD says the lead closes it). (f) release-v0-31-0: step 4 becomes 'retro-report's retro-v0.31.0 story over v0.27.2..v0.31.0 is done, with its retro file on main, before the cut'. A new step quotes board/retros/v0.31.0-checkpoint.md's Checkpoint and Retro sections in the release PR body. Its Done when gains 'This story's file leaves the board: swarm.sh finish release-v0-31-0 once every item above holds', as in release-v0-30-0.md:30. (g) The PR body records two things. codex-agent-name was absorbed by lead-woken's #691 story (its file was deleted in #728, 2f4852d1). The seven standing kind: lead steps (config-switch-ons, flow-after-the-epic, merge-agent-on, merge-queue-on, merge-admin-on-for-infrafactory, merge-agent-for-infrafactory, review-yield-tuning) are retro-v0.31.0's to close or re-date, not this epic's.

**Done when:**
- The board PR has merged. On main, ppid-check-after-review has `epic: board-loose-ends` and no `after:`. unsent-resend-real-pane, reference-split-lead-steps and release-v0-29-0 are gone, or re-homed as the user said. sonnet-share-on is re-homed or gone, as the user decided.
- release-v0-31-0.md on main has the new step 4, the readings step, and the finish line in its Done when.
- The PR body has the user's confirmation of each close reason, the codex-agent-name record, and the seven standing steps named as retro-v0.31.0's.
- ppid-check-after-review's Done when on main says its result is recorded in the PR that finishes it, with no release-v0.29.0 reference left.
- If the user closes sonnet-share-on, the config PR setting `sonnet_share = 0` has merged.

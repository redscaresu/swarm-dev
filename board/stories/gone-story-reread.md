---
kind: code
status: ready
epic: lead-woken
depends_on: []
touches: [bin/lib/board.sh:fm, bin/lib/board.sh:get_fm, bin/lib/board.sh:pr_stories, bin/lib/board.sh:pr_held, bin/lib/merge.sh:merge_caller, bin/lib/lifecycle.sh:stories_fm, tests/merge_rules_test.sh:gone story cases, tests/wait_lead_test.sh:gone story case, docs/lead-by-hand.md:#691 entry, board/stories/codex-agent-name.md]
estimate_lines: 160
easy: false
risk: high
---

# merge and wait --lead read on when a concurrent merge deletes a story file (#691)

#691: `swarm.sh merge` refused 'a story on the board cannot be read' right after another merge deleted a story file (merge.sh:156). wait --lead prints sed: and awk: 'can't open file' noise in the same race (board/stories/codex-agent-name.md). The shared cause: board stories lists a file (board.sh:65-72), a merge deletes it, then fm (sed, board.sh:5) or get_fm (awk, board.sh:2236-2241) reads it. Fix it there. fm and get_fm read a file that is gone as having no value, with nothing on stderr. A file present but unreadable fails as today. pr_stories (board.sh:1166-1178) is the read that merge_caller (merge.sh:156), pr_held (board.sh:1160-1165) and grants (board.sh:1584) refuse on. When a listed file is gone, it lists the board again once and reads again. A second miss, or a file present and unreadable, still fails, so pr_held still holds and merge_caller still refuses. stories_fm (lifecycle.sh:3253) skips a file gone between its glob and its read, with no awk error. The test may make the race deterministic any way it likes; say how in the PR. The PR deletes board/stories/codex-agent-name.md (its Done when is met here) and docs/lead-by-hand.md's #691 entry (59-64), and says Closes #691. Risk high: fm and get_fm are read at about 200 sites, and pr_stories is the fail-closed read behind merge_caller's identity check (merge.sh:156), pr_held's costs-money hold (board.sh:1162) and grants. A re-read after a gone file must still fail closed on an unreadable file that is not gone. merge-safety (not yet planned) also adds cases to tests/merge_rules_test.sh; this story's part is `gone story cases`.

**Done when:**
- tests/merge_rules_test.sh gone story cases: with another story file deleted between the board's list and its read, a merge from review-<slug>'s pane of story <slug>'s PR goes ahead and prints no 'cannot be read' line and no sed: or awk: line.
- A story file present but unreadable (chmod 000) still refuses with 'cannot be read' (the case at tests/merge_rules_test.sh:432-435 passes), and pr_held still holds.
- tests/wait_lead_test.sh gone story case: a poll during which a story file goes prints no sed: or awk: line on stderr, and its other lines as before.
- Removing the re-list from pr_stories turns the merge case red (copy-aside proof).
- board/stories/codex-agent-name.md and docs/lead-by-hand.md's #691 entry are gone; tests/doc_check_test.sh passes.
- An unreadable story file that still exists (chmod 000 fixture) still fails the costs-money hold and merge_caller closed; only a file that is gone is re-read.

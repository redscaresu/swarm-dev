---
kind: code
status: blocked
epic: merge-mechanics
depends_on: [release-upgrade-confirm]
needs: [release-upgrade-confirm (its change to merge_pr's option loop; merged first; so the head check here edits merge_pr from that code.)]
touches: [bin/lib/merge.sh:merge_pr head check, bin/lib/merge.sh:base_merges_only (new), docs/reference-merging.md:Held for dropped base lines, tests/merge_base_accept_test.sh (new), bin/lib/merge.sh:dropped_lines fetch (extracted to a shared helper), docs/reference-merging.md:merge --head paragraph (85-87), docs/reference-building.md:merge --head sentences (814-816, 980-982), docs/reference-lead.md:merge --head sentence (392)]
estimate_lines: 240
easy: false
risk: high
---

# merge takes a head that adds only clean merges of the base to the reviewed head, with no new review

Needs from release-upgrade-confirm: its edit of merge_pr's option loop (shared part merge_pr); start from its merged code. HLD:489-492: the lead ran `git show --remerge-diff` by hand 13 times and each removed 0 lines. The replay half shipped: dropped_hold (bin/lib/merge.sh:847) runs dropped_lines (776, bin/lib/dropped_lines.py) over every merge commit on the head and holds one that drops a base line (#730, #735, #742; tests/dropped_lines_test.sh). Not shipped: merge --head <reviewed> refuses any other head (merge_pr, merge.sh:1036: `the head of <url> is X, not Y: review the new head`), so a builder's clean merge of the base costs a new review. Change: when the head is not <want>, accept it when every commit on the head's first-parent chain back to <want> is a two-parent merge whose second parent is on the base and whose remerge-diff is empty (git's own merge, no hand edit), and print one line naming the merges accepted and the reviewed head. A merge with a non-empty remerge-diff (a resolved conflict) refuses as today: the resolution is new code. Any non-merge commit refuses as today. dropped_hold then runs on the new head as now. Use dropped_lines' private fetch of refs/pull/<n>/head (no FETCH_HEAD, refs of the run's own) and its git floor (DROPPED_GIT_MIN, merge.sh:39); a git below it refuses as today. Keep the check in one new helper under ~150 lines. No brief change: an accepted head ends in `merged:` as before (the review agent's brief, build.sh:1392-1401, is review-follows-head's part). Require <want> to be on the head's first-parent chain (`git merge-base --is-ancestor <want> <head>` and found by walking first parents), so a head built by resetting to <want>~1 and merging the base is refused. Order: under `merge --head <reviewed>`, a merge commit that drops a base line has a non-empty remerge-diff and is refused at the head check with `review the new head`, before dropped_hold runs; say so. Extract dropped_lines' inline fetch (merge.sh:795-806) into a shared helper both use, and run the new check in its own subshell with the dropped_refs_drop trap, as dropped_hold does (merge_pr's base_wait replaces the EXIT trap at merge.sh:684). This story covers merge --head (the lead's next exit, lifecycle.sh:4004, and the user); the review agent's `review --head` route is review-accepts-base-merge's. Docs that say merge --head refuses any pushed head change with it: docs/reference-merging.md:85-87, docs/reference-building.md:814-816 and 980-982, docs/reference-lead.md:392.

**Done when:**
- A new tests/merge_base_accept_test.sh: a reviewed head plus one clean merge of the base: `merge --head <reviewed>` reaches the stub's `pr merge` with `--match-head-commit <new head>` and prints the accepted line.
- Same file: under `merge --head <reviewed>`, a merge that drops a base line is refused with `review the new head` and is never merged.
- Same file: a conflicted merge (non-empty remerge-diff) is refused with `review the new head`, not merged.
- Same file: a non-merge commit after the reviewed head is refused as today.
- Same file: a head that is a clean merge of the base into <want>~1 (the reviewed commit gone) is refused.
- No refs/swarm/dropped-lines/* ref is left after an accept or after a refuse.
- docs/reference-merging.md's 'Held for dropped base lines' paragraph and the four places that say merge --head refuses any pushed head say when merge takes a new head without a review; tests/doc_check_test.sh passes.
- The PR body shows the clean case red with the acceptance removed, and the conflicted case merging (red) with the remerge-diff check removed.

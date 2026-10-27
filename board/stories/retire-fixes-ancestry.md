---
kind: code
status: ready
epic: merge-holds
depends_on: []
touches: [bin/lib/merge.sh:retire_fixes, bin/lib/merge.sh:fix_main output, docs/reference.md:fix-main, tests/retire_fixes_ancestry_test.sh (new)]
estimate_lines: 160
easy: false
---

# retire_fixes picks the older fix-main story by commit ancestry, not by log order

retire_fixes (bin/lib/merge.sh:766-774) treats a red as older when its main-red line was logged first.
- On 2026-10-26, 83b2e54's red was logged at 07:06 and 0ec59b6's at 07:09 (.swarm/events.tsv:1791,1803), though 83b2e54 descends from 0ec59b6. fix-main-0ec59b6 was written and held twice (:1804,:1807) until main went green at 07:28 (:1843).
- Worse, fix_main for 0ec59b6 would have retired fix-main-83b2e54, the newer red's fix, had its build not started.
- Change it so that, for a key, an unstarted ready fix-main-<s> story retires when another red of that key, in either log order, descends from <s> (ref_in, merge.sh:1712, after fetch_branch of the base). It is then `superseded by fix-main-<descendant>`. A story whose red descends from the others stays.
- Ancestry is read only in PROJECT_DIR's clone, and only for a key whose owner/repo is that clone's origin (main_key carries owner/repo, merge.sh:662). A red in another repo retires nothing by ancestry, since its commits are not in this clone.
- If the ancestry cannot be read (fetch fails, sha missing), retire nothing for that pair. One story too many beats a lost fix.
- `retire_fixes <key> -` (clear_red_main) still retires every unstarted fix of the key, in any repo.
- When fix_main's own new story retires at once, its output names the story that covers the red, not the retired file.
- Docs: retire_fixes' header and docs/reference.md's fix-main paragraph (:2085-2087).
- The new test file uses small fixtures and stays out of SLOW (Makefile:20-26). If it must join SLOW, this PR edits the Makefile, a protected path, and ci.yml's shard count (tests/test_shard_test.sh), so the PR waits for the user's merge. Say so in the PR.

**Done when:**
- tests/retire_fixes_ancestry_test.sh (new; a git fixture with commits A then B, B descending from A): the main-red for B is logged before A's, and neither story has started. After fix_main for A, fix-main-B is on the board, fix-main-A is gone, and events.tsv says `retired: superseded by fix-main-<B>`.
- Same file: with A's red logged first, B's red retires fix-main-A as today. Two reds where neither descends from the other leave both stories. An unreadable ancestry leaves both.
- Same file: two reds under a key whose owner/repo is not PROJECT_DIR's origin, logged out of order, leave both stories. A green on that key (`retire_fixes <key> -`) still retires them.
- Same file: fix_main's output for A names fix-main-B as the story covering the red.
- tests/merge_test.sh's retire cases (:109, :185) pass unchanged.
- The PR body says the out-of-order case failed on main's retire_fixes in a copy of the checkout.

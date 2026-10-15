---
kind: code
status: blocked
blocked_by: [story-after-unmerged-close]
epic: flow-speedups
depends_on: [story-after-unmerged-close]
touches: [bin/swarm.sh:reconcile (pre-pull restore), bin/swarm.sh:pull_board_repo, tests/review_test.sh (reconcile block), docs/method.md (§ Building, **Merging.**, the reconcile sentences), bin/swarm.sh:set_fm / SET_FM_KEYS]
risk: high
---

# reconcile's pull keeps the board's uncommitted status flips on files the merge also changed, and takes a file the merge deleted as deleted

Today only merged items get their swarm keys put back before the pull (bin/swarm.sh:2341-2352). An unblock flip on another story the pull touches stops the pull, and reconcile dies (:2369-2406). Generalise this to every ` M` board file whose only difference from HEAD is in swarm keys (status, blocked_by, SET_FM_KEYS): save those values, check the file out, pull, then re-apply them if the file still exists. If the merge deleted the file it stays deleted, with a line naming it. A file with any other difference (a hand edit) still stops the pull and is left as it was. The backup and restore-on-failure stay as they are.

**Done when:**
- tests/review_test.sh: story x is flipped uncommitted (blocked to ready, blocked_by dropped) and upstream's merge changes x's body. reconcile exits 0, and x has upstream's body with status: ready and no blocked_by.
- A flip on story y that upstream deleted: y is gone after reconcile, a printed line names it, and the exit is 0.
- A hand edit to x's body still stops the pull, naming x, and leaves x byte-for-byte as it was.
- The existing reconcile cases in tests/review_test.sh pass unchanged.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs/commands prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Swarm keys are status, prs, blocked_by and SET_FM_KEYS (add blocked_by and prs to SET_FM_KEYS or handle them alongside; add set_fm/SET_FM_KEYS to touches).
- Merged items keep today's path: back to HEAD, no re-apply.
- Every other key is re-applied only where upstream's value equals HEAD's (a three-way rule). Otherwise the pull stops, naming the file, and leaves it byte for byte.
- Every file the step checks out goes into the same backup, and a failed pull restores all of them.
- Extra Done when: (a) upstream sets x to status: blocked with blocked_by while x is flipped to ready locally: reconcile stops naming x, and x is unchanged; (b) a flipped non-merged x with a diverged main (the tests/review_test.sh:130 setup): after the failed pull x still has its flip; (c) upstream changes x's body while x's status is flipped locally: the pull succeeds and x has both; (d) an unrelated in-review story with a prs: line and an upstream body change pulls cleanly.

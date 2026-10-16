---
kind: code
status: blocked
blocked_by: [blocked-by-from-depends-on]
epic: leaner-faster-swarm
depends_on: [blocked-by-from-depends-on]
touches: [bin/swarm.sh:reconcile (the pull condition only), tests/review_test.sh:reconcile cases]
---

# `swarm.sh reconcile` pulls the main checkout whenever it is behind, not only when a review item merged

reconcile (bin/swarm.sh:3068) calls pull_board_repo (:3683) only inside the branch for review
items whose PRs all merged (:3121). A PR the lead merges directly (a one-off under merge = human, a
board PR) has no review item, so reconcile prints nothing and leaves the main checkout behind. The
lead then pulls by hand; on 2026-10-16 a hand stash-pull-pop deleted a live story (restored).

reconcile runs pull_board_repo whenever the checkout has an upstream and is behind it
(`HEAD..@{upstream}` non-empty after a fetch), whether or not any item merged: when no review item merged, it pulls at the point where the
merged-items path pulls today. The merged-items path keeps its SET_FM_KEYS put-back and its restore on failure; a pull
with no merged item that fails dies with the same message, touching nothing. When nothing is
behind, no pull is attempted and the output is unchanged. Waits on blocked-by-from-depends-on, which
changes SET_FM_KEYS and key_clash that pull_board_repo uses.

bash 3.2. shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and
`claude plugin validate .` must pass. Leave docs and commands to method-guide-and-reference and
readme-and-agents; decline as out of scope any review finding about them.

**Done when:** tests/review_test.sh (local bare origin and a clone), each case shown failing with
the change reverted (FAIL lines in the PR body):
- a commit lands on origin's base that deletes a story with no review item, and the clone has an
  uncommitted status flip on a different story: `swarm.sh reconcile` fast-forwards the clone, the
  deleted story is gone, and the flip is still there.
- the same with a modified file outside the board: reconcile refuses with its cannot-pull message
  and HEAD and the working tree are unchanged.
- origin not ahead: reconcile prints what it printed before this change, and HEAD is unchanged.
- the existing reconcile cases pass unchanged.

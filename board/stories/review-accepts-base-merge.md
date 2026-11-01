---
kind: code
status: blocked
epic: merge-mechanics
depends_on: [merge-accepts-base-merge, next-follows-moved-head]
needs: [merge-accepts-base-merge (the base-merges-only helper in bin/lib/merge.sh), next-follows-moved-head (review_heads' moved-head refusal message (board.sh:2589); the same part)]
touches: [bin/lib/board.sh:review_heads (base-merge acceptance), tests/review_agent_test.sh:review --head base-merge cases (new), docs/reference-building.md:review --head sentence]
estimate_lines: 120
easy: false
---

# review --head accepts a reviewed head plus clean base merges, as merge --head does

Needs from merge-accepts-base-merge: its base-merges-only helper; and from next-follows-moved-head (review-follows-head): its change to review_heads' moved-head refusal message, the same part. The review agent runs `review <slug> --head <reviewed>` before `merge --head` (bin/lib/build.sh:1390, review_handoff), and mark_review's review_heads (bin/lib/board.sh:2531, 2589) refuses any other head, as does the lead's unmerged: line, which needs a pass on the current head (lifecycle.sh:2910). So after merge-accepts-base-merge a builder's clean merge of the base after a pass still ends in `head moved:` and a new review agent on the main route. Change review_heads to accept the new head when the base-merges-only helper accepts it (only clean two-parent merges of the base on the first-parent chain from the reviewed head), record the pass on the new head with the reviewed head named, and print one line saying so. Anything else refuses as today, with the message next-follows-moved-head wrote. Docs: docs/reference-building.md's review --head sentence.

**Done when:**
- tests/review_agent_test.sh: a pass recorded on H1, then one clean merge of the base pushed as H2: `review <slug> --head H1` records the pass on H2, names H1, and the story is in review.
- The same with a merge whose remerge-diff is not empty, or a non-merge commit, is refused as today.
- With the acceptance removed (copy-aside proof) the first case goes red; the PR pastes the FAIL line.
- tests/doc_check_test.sh, shellcheck and scripts/select-tests.sh --run pass.

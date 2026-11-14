---
kind: code
status: blocked
epic: retro-gate
depends_on: [non-fix-change, next-retro-step]
needs: [non-fix-change (non_fix_change; run before release_stage answers patch), next-retro-step (release_repo's stub gh; its docs/reference-merging.md § Releases edit lands first (a shared part))]
touches: [bin/lib/board.sh:release_stage (the patch answer and its comment), tests/next_test.sh:staged patch cases (:885-964), docs/reference-merging.md:Releases (stage paragraph's patch sentence)]
estimate_lines: 80
easy: true
---

# next offers no patch while a change since the tag is not a fix

Needs from non-fix-change: non_fix_change. Needs from next-retro-step: release_repo's stub gh, and its § Releases first-paragraph edit on the base first (a shared part). release_stage (bin/lib/board.sh:1239-1306) answers 'patch <x.y.z+1>' when a stage is held and no staged story merged since the tag. Its comment says nothing checks that the patch is a fix (:1234), and release-retro-gate will refuse a patch with any non-fix change. Before it prints patch (:1304), run non_fix_change <origin_repo> <the local tag's commit> origin/<base>. When that prints a change or fails, answer held instead. End the release-held: line with '; no patch: <first change line>' or '; no patch: <the failure>'. The bare and 'release <S>' answers are unchanged. Fix the :1234 comment. In tests/next_test.sh's stage block, map each patch case's commits (:885-964) to a fix: true story PR through release_repo's stub gh, so they still give release v1.2.1 (patch). The git-log count (:978-980) stays 1, because non_fix_change runs no git log. In docs/reference-merging.md § Releases' stage paragraph (:946-948), say a patch also needs every change since the tag to come from a fix: true story or a fix-main build. bash 3.2; one sentence per line.

**Done when:**
- tests/next_test.sh: a held stage (STAGE, REVIEW) with a commit since v1.2.0 from a story PR with no fix: line gives no release step, and its release-held: line names that commit. Mapped to a fix: true story, it gives `release v1.2.1 (patch)`. A commit no PR lists gives no release step.
- Same file: a non-fix story merged before the tag, still on the board at done, plus a fix: true story after the tag, gives `release v1.2.1 (patch)`. The existing patch cases still give it. The git-log count still reads 1 once a release is due, and 0 when none is.
- The new cases fail on a worktree copy with the non_fix_change call removed from release_stage; the PR body has the FAIL lines. tests/doc_check_test.sh passes.

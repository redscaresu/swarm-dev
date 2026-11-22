---
kind: code
status: ready
depends_on: []
touches: [bin/lib/merge.sh:dropped_lines (the merge-commit check), tests/dropped_lines_test.sh:merged-parent cases, docs/reference-merging.md:§ Merging (the dropped-lines hold)]
estimate_lines: 180
fix: true
---

# dropped-lines can check a stacked build's merge of a parent that has since merged

On 2026-11-21 and 22, every stacked build's review stopped at dropped-lines, some twice:
- port-checks: #1060, #1062, #1064, #1066.
- binary-fetch: #1126, #1129, #1131, #1135.

dropped_lines (bin/lib/merge.sh:886) stops on a merge commit in the PR's history whose parent is not on the base. Its messages are "neither parent is on <base>" and "its first parent holds commits ... that the merged parent's branch lacks". Main squash-merges, so the parent branch's commits never reach main even after its PR merges. Merging main on top does not remove the old merge. The lead had the builders squash their branches onto main by hand each time. This was logged as dropped-lines-stacked-build (deferred) on #1066 and as a lead-hand intervention.

- When a merge commit in the PR's history merges a branch whose PR has since merged into the base, check it against the base's squash commit for that PR. Find that commit from the PR's merge commit: `gh api repos/<o>/<r>/pulls/<n> --jq .merge_commit_sha`. Do not stop because the parent's own commits are not on the base.
- A merge of a parent whose PR is still open, or closed unmerged, keeps today's answer: unchecked, so the review stops.
- Docs move with it: docs/reference-merging.md § Merging, where it describes the dropped-lines hold.

**Done when:**
- A new case in tests/dropped_lines_test.sh, under the existing fixtures with a gh stub, builds a stacked branch. It merges parent branch P into child C, then squash-merges P into the base as commit S, and the stub answers P's PR with merge_commit_sha S. dropped-lines on C's head exits 0 when C keeps every base line, and names the line when C drops one.
- A second case, with P's PR still open, keeps today's unchecked answer.
- The new case goes red when the merged-parent branch is removed (proved on a copy of the worktree without .git).
- scripts/select-tests.sh --run passes

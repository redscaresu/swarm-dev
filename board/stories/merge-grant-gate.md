---
kind: code
status: blocked
epic: hld-grants
depends_on: [grants-reader]
needs: bin/lib/board.sh item_hld and hld_grants, and the PR resolution behind swarm.sh grants
touches: [bin/lib/merge.sh:merge_caller and merge_pr, tests/merge_test.sh]
estimate_lines: 140
easy: false
risk: high
---

# Under merge = human, swarm.sh merge refuses the lead unless the PR's HLD grants merge

Needs grants-reader's PR resolution, the same one `swarm.sh grants <PR URL>` prints.

Today merge_caller (bin/lib/merge.sh:~109) lets the lead merge whatever `merge` says, so "the user merges under human" is only prompt text, and tests/merge_test.sh:1017-1019 pins the lead merging under human. After this story:
- With `merge = human`, merge_pr refuses a story PR or `--board` PR from the lead unless the PR resolves to an agreed HLD whose grants include `merge`. The refusal says: `<PR> waits on the user's merge (merge = human, and no HLD grants merge for it)`. Flip the test at 1017-1019 to expect that refusal, and add one where the grant opens it.
- When a grant opens a merge under human, the holds that run under `merge = agent` run too: pr_held (bin/lib/merge.sh:173-177), and costs_diff for a board PR (209-214). A `costs: money` PR stays held whatever the grant says, as the parent requires.
- `merge = agent` is untouched: every existing agent-mode test passes unchanged. Builders and conductors are refused as they are today. hooks/merge-guard.sh is unchanged.
- `--release` is not touched here; release-grant-gate does that.

risk: high because this changes who may merge.

**Done when:**
- tests/merge_test.sh with a stub gh, under `merge = human`: a story PR under an HLD with no `merge` grant is refused with that message; the same PR with `grants: [merge]` merges; a `costs: money` story under the grant is held; a board PR touching epics under two HLDs is refused.
- Every `merge = agent` case passes unchanged.
- `make test` passes.

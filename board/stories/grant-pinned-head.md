---
kind: code
status: ready
risk: high
depends_on: []
touches: [bin/lib/merge.sh:merge_grant, bin/lib/board.sh:pr_hld head read, tests/grant_pinned_head_test.sh (new)]
estimate_lines: 60
easy: false
---

# The merge grant judges the head that merges

`merge --head <sha>` pins the head it will merge. But `merge_grant` and `pr_hld` read the PR's `headRefOid` again from GitHub and judge the files at that head (conduct-plan-hld report, 2026-10-24). A push between the pin and the grant read means the grant judges one head while another merges: either the pinned one (`gh pr merge --match-head-commit` then refuses), or a later push lands whose files the grant judged under a different SHA. Close the gap, as a grant must fail closed.

- `merge_grant` and `pr_hld` take the pinned head SHA from `merge_pr` and read the file list at that SHA. If the PR's current head differs from the pin, the grant resolves to none and says why.
- `swarm.sh grants <PR>` without a pin keeps reading the current head.

**Done when:**
- tests/grant_pinned_head_test.sh, with stubbed gh: a PR whose head moves after the pin (the new head adds a `.github/workflows/` file) resolves to none under `merge --head <old>`. An unmoved head still resolves to its HLD.
- `make test` passes.

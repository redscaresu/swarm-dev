---
kind: code
status: blocked
epic: plan-hld
depends_on: [grants-hld-arm]
needs: grants-reader (merged) pr_hld and one_hld in bin/lib/board.sh
touches: [bin/lib/board.sh:pr_hld, tests/grants_test.sh]
estimate_lines: 100
easy: false
risk: high
---

# The merge grant covers /plan-hld's board PR

Uses grants-reader's pr_hld (bin/lib/board.sh:617-673), merged. Shares tests/grants_test.sh with grants-hld-arm, so it builds after it. Run the epic's **Checks before every stage**.

Today pr_hld puts any PR that touches the board's `hld/` under none (board.sh:~647), so an HLD that grants `merge` never covers its own planning PR, which edits the HLD: the parent's goal 2 promises it does (board/epics/retro-and-shared-rules.md:61). After this story, a PR in the project's repo that touches exactly one `<board>/hld/<H>.md` is attributed to H when:
- the HLD as the board has it is agreed, and its head copy (fetched as the epics are, through `gh api ...contents?ref=<head>`) differs from it only in a `planned:` front-matter line and lines inside the `## Epics` section (heading to the next `## ` or EOF);
- every other file the PR touches is an `epics/*.md` whose head copy carries `hld: H`, read through item_hld as today, so one_hld still has to agree on H.

Any other change to the HLD (status, grants, any other body line, deleting it), a second HLD file, or `.claude/swarm/` keeps the PR under none. The HLD is still read as the board has it, so a PR cannot grant itself. The finish PR deletes the HLD and stays under none: the parent requires the user to merge it (retro-and-shared-rules.md:84).

risk: high because it widens what the lead may merge.

**Done when:**
- tests/grants_test.sh with a stub gh: a PR adding two epics with `hld: H` and setting `planned:` plus `## Epics` links on agreed H resolves to H, and to none under a draft H; a PR that also changes H's `status:` or `grants:`, or one body line outside `## Epics`, resolves to none; a PR touching H and a second HLD resolves to none; a PR deleting H resolves to none; an added epic with `hld:` naming another HLD resolves to none.
- tests/merge_test.sh is not touched here; `swarm.sh grants <PR URL>` is the seam merge-grant-gate already reads, so under `merge = human` the plan PR merges with `grants: [merge]` and waits without it (one grants_test case asserts both grant outputs).
- Every existing grants_test case passes unchanged.
- `make test` passes.

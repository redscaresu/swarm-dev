---
kind: code
status: ready
depends_on: []
touches: [bin/lib/merge.sh:merge_pr --board branch, tests/merge_board_root_test.sh (new)]
estimate_lines: 30
easy: true
---

# merge --board works when the board is the project root

`merge_pr`'s `--board` branch sets `rel="${BOARD#"${PROJECT_DIR}"/}"` (bin/lib/merge.sh:265). When `board_dir` is the project root, `BOARD` equals `PROJECT_DIR`, so `rel` stays the whole absolute path. Every board merge in such a project is then refused. Lines :734 and :769 already handle that case (`[[ "${BOARD}" == "${PROJECT_DIR}" ]] || rel=...`). Found by conduct-epic-guard on #450 (2026-10-24), and present before that PR.

- Treat the board-at-root case at :265 the way :734 does.

**Done when:**
- tests/merge_board_root_test.sh (new): with `board_dir = .`, `merge --board` of a PR that changes only stories/ and epics/ files passes the board-only check, and one that also changes a file outside them is still refused.
- `make test` passes.

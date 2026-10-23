---
kind: code
status: blocked
epic: hld-grants
depends_on: [merge-grant-gate]
needs: bin/lib/merge.sh merge_pr's human-mode refusal, which this extends to --release
touches: [bin/lib/merge.sh:release_check, tests/merge_test.sh]
estimate_lines: 120
easy: false
risk: high
---

# Under merge = human, merge --release needs every story since the last tag to sit under HLDs that grant release

Needs merge-grant-gate's refusal of the lead under merge = human, in merge_pr.

A merged story's file has left the board, so release_check cannot read its epic from the board. It reads them from git instead. For every `stories/*.md` deleted on the base branch since the last `v` tag (`git log <tag>..<base> --diff-filter=D --name-only`), it reads the file at the deleting commit's parent, and resolves it with grants-reader's item_hld against the epics and HLD at that commit, or on the board when they are still there. The release is covered when there is at least one such story and every one resolves to an agreed HLD that grants `release`. Under `merge = human`, `merge --release` from the lead is refused unless the release is covered. The refusal names the first uncovered story. The docs gate (release_docs) runs as today, whatever the grant says.

`merge = agent` is untouched.

**Done when:**
- tests/merge_test.sh with a stub gh and a fixture repo with a tag, under `merge = human`: a release whose stories since the tag are all under an HLD granting `release` merges; one with a story under no HLD is refused, naming it; a covered release with code changes and no docs or `Docs: none` line is still refused by the docs gate.
- Every `merge = agent` release case passes unchanged.
- `make test` passes.

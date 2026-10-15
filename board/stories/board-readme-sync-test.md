---
kind: code
status: ready
epic: lead-loop
depends_on: []
touches: [tests/board_readme_test.sh (new)]
---

# A test fails when swarm-dev's board/stories/README.md and templates/docs/stories/README.md differ

New tests/board_readme_test.sh in the style of tests/command_names_test.sh (REPO-relative, no stubs): cmp -s board/stories/README.md templates/docs/stories/README.md, exit 1 naming both paths and printing their diff when they differ. The two are identical today (diff empty), so the test also runs its own compare function on two temp copies that differ by one line and fails if that reports a match, so it cannot pass vacuously. swarm-dev's own board only: nothing a user project copies changes. No README or docs change (nothing a user runs or sees).

**Done when:**
- bash tests/board_readme_test.sh exits 0 on the branch and prints an ok line.
- With one line appended to board/stories/README.md (backed up and restored with cp), it exits non-zero and names both files; the PR shows that run.
- If its compare function is replaced by one that always matches, the temp-copy self-check fails the test.
- shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

---
kind: code
status: blocked
epic: first-port
depends_on: [first-port-freeze-start]
needs: first-port-freeze-start (its **You:** steps: the freeze is on, so the epic may start)
touches: [tests/removed_test.sh:files list, header and ok line, scripts/test-map.tsv:Go row]
estimate_lines: 20
easy: true
---

# Tests-only: removed_test.sh's removed-name grep also reads every Go file under cmd/ and internal/

Needs first-port-freeze-start's **You:** steps: the freeze is on. The go_check of docs/port/tests.tsv:119. It is an edit to the bash grep, not a Go check: the row asks the grep to read more files, and the grep stays under tests/ after the bash is gone.
- tests/removed_test.sh's files list (:24-25) gains every .go file under cmd/ and internal/, testdata included. Find them with find and a loop that bash 3.2 runs: no mapfile and no globstar.
- The header (:2-3) and the ok line (:30) name them. GONE and the REMOVED_KEYS exception stay as they are.
- scripts/test-map.tsv's Go row (:61) gains tests/removed_test.sh, so a Go change selects it. trusted-go-port copies this row's tests into the row it adds above it, so it waits for this story.
- No Go file names a removed name today (grep at 0d9729f7), so the check passes at once.

**Done when:**
- (1) tests/removed_test.sh passes, and its ok line names cmd/ and internal/. (2) On a copy of the worktree without .git, the removed name keep_panes added to a comment in internal/clock/clock.go, and in a file under internal/layers/testdata/, each turns the check red, naming the file. The FAIL lines are in the PR body. (3) In a scratch clone outside the worktree whose only changes against origin/main are this PR's scripts/test-map.tsv and a comment in internal/clock/clock.go, scripts/select-tests.sh --known lists tests/removed_test.sh; the PR body shows the run. (4) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: code
status: ready
epic: binary-wrapper
depends_on: []
touches: [tests/command_names_test.sh:bare /swarm scan, scripts/test-map.tsv:Go row]
estimate_lines: 25
easy: true
---

# command_names_test scans the Go files for a bare /swarm

Needs no other story; tests only. Its go_check (docs/port/tests.tsv:31): the bare /swarm scan (tests/command_names_test.sh:19-20) also reads every Go file under cmd/ and internal/, since the Go will print the messages users read. internal/ does not exist yet. A grep over a missing path exits 2, and `|| true` would hide it, so scan only the Go files that exist, and fail when cmd/ gives none (a positive control). The test map's Go row (scripts/test-map.tsv:52) omits command_names_test.sh, so a Go-only change would not select the new scan (scripts/select_tests.py:153): add it to that row and to the row's comment (codex). marker-dispatch also edits that row and waits on this story.

**Done when:**
- The test passes on the tree, and its ok line names how many Go files it scanned (at least one).
- Proof in the PR, on a no-.git copy: a bare /swarm in a string in cmd/swarm/main.go makes it fail, naming the file and line; with cmd/ holding no Go file it fails saying it scanned none.
- scripts/select-tests.sh, given only cmd/swarm/main.go as changed, lists tests/command_names_test.sh; the PR shows the output. tests/select_tests_test.sh passes.
- scripts/select-tests.sh --run passes

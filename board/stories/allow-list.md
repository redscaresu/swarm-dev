---
kind: code
status: blocked
epic: port-checks
depends_on: [diff-run-core]
needs: diff-run-core (tests/diff_run.sh: the per-fixture, per-stream differences and the stream names hunks address)
touches: [tests/diff_run.sh:stage option and allow lists, tests/diff_run.sh:draft option, tests/diff_run.sh:only option, scripts/allow/README.md, scripts/test-map.tsv:allow row, tests/diff_allow_test.sh]
estimate_lines: 290
---

# Stage allow lists name each allowed difference by its exact lines

Uses diff-run-core's per-fixture, per-stream differences and its stream names. `--stage N` reads scripts/allow/stage-1/ through stage-N/. Each is a directory with one file per story, <slug>.md, so two PRs never edit one file; with one file per stage, every stage 1 PR would append to its end. An entry file gives the story slug, its PR, its kind (fix for a fix: true story, stage for a change the stage makes on purpose) and hunks. A hunk names a fixture, a stream (stdout, stderr, exit, file:<path>, calls:<step>) and the exact lines removed and added; an insertion names the line it follows. Entries apply to the old tree's output in the order their PRs merged, and the result is compared with the new tree's. A difference no hunk covers is red, and so is a hunk that does not apply on a fixture the run ran. A hunk for a fixture outside the run is skipped. A hunk with no lines, or one naming a whole fixture, stream or file, is refused. `--only <slug>` applies one story's entry alone, to check it against that story's own merge commit. `--draft` prints the differences as hunks to edit. scripts/allow/README.md gives the format and says the user agrees each stage's list at its exit. scripts/* does not span directories, and select_tests_test.sh fails a tracked scripts/ file that no row matches (scripts/test-map.tsv:3-13,37). So a row sends scripts/allow/** to tests/diff_allow_test.sh, which parses every entry file on disk.

**Done when:**
- (1) In tests/diff_allow_test.sh, on two copies with a seeded change, each of these is red: the change with no entry; a hunk whose removed line is one byte off; an entry with its lines left out; a hunk naming a stream with no lines; a hunk that does not apply on a fixture the run ran. (2) A calls:fg hunk for one extra gh call applies. (3) An entry in stage-2/ applies at `--stage 2` and is red at `--stage 1`. (4) `--only a` applies a's entry and leaves b's out. (5) Every entry file on disk parses, and a malformed one added on a copy is red. (6) Each proof is made on a worktree copy without .git, and the test runs in under 120 s on its CI shard.
- scripts/select-tests.sh --run passes

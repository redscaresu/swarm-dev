---
kind: code
status: ready
epic: test-speed
depends_on: []
touches: [scripts/select-tests.sh, scripts/select_tests.py, scripts/test-map.tsv, tests/select_tests_test.sh, .github/workflows/ci.yml:shellcheck step, .github/workflows/ci.yml:compile step, README.md:selector line in More]
estimate_lines: 280
easy: false
---

# A selector picks the test files for a branch's changed files, and the full suite whenever it is unsure

New scripts/select-tests.sh (bash entry) and scripts/select_tests.py (its logic, python3 like bin/lib's helpers). It takes the files the branch changed against its merge base with origin/main, committed, uncommitted and untracked (`git status --porcelain`), a rename by both paths, and prints the tests/*_test.sh files to run, one per line, from scripts/test-map.tsv (a row per tracked path or glob: test files, `named`, `all` or `none`). `named` means every test whose text names the file's path or basename, found at run time, so a new reader is picked up. In this story bin/swarm.sh, bin/lib/*.sh and bin/lib/*.py map to `all` (select-tests-by-reach narrows them). scripts/test.sh and Makefile map to `all`: test.sh sets every test's environment (scripts/test.sh:34-40). README.md, AGENTS.md and docs/** map to `named` with a floor of doc_check_test, features_test and llms_test (epic Done when 1) plus the seven tests that read the real docs: config_test.sh:207, epic_codex_test.sh:25-30, board_pr_test.sh:483, merge_test.sh:1944, skill_test.sh:58-62, removed_test.sh:56, flow_sections_test.sh:15. commands/*.md, hooks/*, other scripts/* and bin/gh-shim/gh map to `named`. A changed tests/x_test.sh selects itself. board/** selects none (CI's board-only gate skips those PRs, scripts/board-only.sh). Fail toward more (epic Constraints): an unmatched path, an untracked path no row matches, or a `named` row that finds no test selects every tests/*_test.sh. A full selection prints every tests/*_test.sh, so scripts/test.sh logs it as `all` (:138-139). `--run` runs `make test TESTS=... JOBS=4` (HLD Appendix C; Makefile:24 defaults to every CPU); an empty selection runs nothing and says so. Add both files to ci.yml's shellcheck and compile steps (.github/workflows/ci.yml:41-44). README.md's More list gets the selector line in this PR (AGENTS.md: README in the same PR). No runner, Makefile or AGENTS.md change.

**Done when:**
- tests/select_tests_test.sh, on a temp git repo with fixture tests, pins one positive case per directory: docs/method.md selects the doc floor plus a fixture test that names it; commands/swarm.md, hooks/merge-guard.sh, scripts/board-only.sh and bin/gh-shim/gh each select the fixture test that names them and not one that does not; scripts/test.sh, Makefile and a bin/lib/*.sh file select every test; tests/x_test.sh selects itself; a board/-only change selects nothing; a rename selects for both paths.
- The same test shows an untracked file no row matches, and a `named` row whose file no test names, each select every test; and `--run` passes JOBS=4 to make (a stub make records its arguments).
- The map test fails, naming the path, on a file list with one unmapped path under each of bin/, scripts/, commands/, hooks/ and docs/, and passes on the repo's own `git ls-files`.

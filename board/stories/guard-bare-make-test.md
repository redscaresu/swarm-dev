---
kind: code
status: ready
depends_on: []
touches: [hooks/merge-guard.sh:agent make test refusal, tests/merge_guard_test.sh:bare make test cases, docs/reference-merging.md:guard paragraph (§ Merging) make test sentence, AGENTS.md:Rules that are not negotiable guard sentence]
estimate_lines: 70
easy: true
---

# The guard refuses an agent's bare make test

After #954 stopped select-tests from running the full suite, one builder still ran a bare
`make test` (no `TESTS=`) for 3h45m on 2026-11-16 (#905's builder, on a head that had already been
rebuilt), and it held the review's findings back the whole time. The v0.31.0 retro (2026-11-17): the
user chose to have the guard refuse it.

In hooks/merge-guard.sh, refuse an agent's `make test` that names no `TESTS=` (and `make -C <dir> test`
the same way), with a message that points at `scripts/select-tests.sh --run` and says CI's sharded run is
the full suite. `make test TESTS=<files>`, `scripts/select-tests.sh --run` and the lead's or a person's
own `make test` still pass, as `make test` started inside a test run does.

**Done when:**
- tests/merge_guard_test.sh: an agent's `make test`, `make test JOBS=4` and `make -C . test` are refused
  with the select-tests pointer; with the check removed each passes (shown on a worktree copy, quoted in
  the PR)
- An agent's `make test TESTS=tests/x_test.sh` and `scripts/select-tests.sh --run` pass
- The lead's session's bare `make test` passes
- AGENTS.md's guard rule and docs/reference-merging.md list the refusal
- scripts/select-tests.sh --run passes

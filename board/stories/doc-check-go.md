---
kind: code
status: blocked
epic: go-module
depends_on: [go-module-build, protected-go-paths, docs-gate-go]
needs: go-module-build (go.mod and cmd/swarm/main.go on disk, as the paths the passing cases name); protected-go-paths (the own-repo protected list in bin/lib/board.sh, and the docs sentences that name its four package paths); docs-gate-go (the docs sentences in docs/reference-merging.md and commands/swarm.md that name the Go tree)
touches: [tests/doc_check_test.sh:ROOTS Go roots, tests/doc_check_test.sh:exists protected Go paths, tests/doc_check_test.sh:check_code go.mod names, tests/doc_check_test.sh:fixture docs Go paths, tests/doc_check_test.sh:header comment]
estimate_lines: 65
easy: true
---

# doc_check fails a doc that names a Go path that does not exist

Uses go.mod and cmd/swarm/main.go from go-module-build, and the docs and own-repo protected list that ship-gates' protected-go-paths and docs-gate-go put on main.
- ROOTS (tests/doc_check_test.sh:36) has no cmd or internal. Add both, so a `cmd/...` or `internal/...` path in a code span or a link must exist.
- After ship-gates, docs/reference-merging.md, docs/reference-planning.md and docs/method.md name internal/guard/, internal/merge/, internal/release/ and internal/agentenv/ (protected-go-paths' Docs). None of those directories exists until the port epics, so with internal in ROOTS, exists() (:38-44) fails them (critic).
- So exists() also passes a path that equals one of the own-repo protected paths in bin/lib/board.sh, or a directory above one (`internal/`). Read that list from the source, as the check reads CONFIG_KEYS from bin/swarm.sh (:35). If its form cannot be read that way, stop and tell the conductor. A file under a protected path, such as internal/guard/nope.go, must still exist. A board.sh change already selects this test (scripts/test-map.tsv:26).
- Do not put these paths in tests/doc_check_known.txt: it lists stale references and only shrinks (:11-13).
- If the real docs name a Go path that neither exists nor is protected, stop and tell the conductor rather than widen the rule.
- go.mod has no slash, so ROOTS never matches it. Check every `go.mod` name, bare or under a directory, against the repo. Do not check go.sum: the Go rules keep it absent (HLD:331), so a doc may name it.
- Add fixture docs next to the wrap.md one (:250-262). `cmd/nope/main.go`, `internal/nope/x.go`, `internal/gaurd/`, `internal/guard/nope.go` and `tools/go.mod` must be flagged. `cmd/swarm/main.go`, `go.mod`, `go.sum`, `internal/guard/` and `internal/` must pass.
- AGENTS.md is checked for links only (:9-10), so a Go path there is not caught. Say so in the header comment, beside the protected-path rule.

**Done when:**
- doc_check_test.sh flags cmd/nope/main.go, internal/nope/x.go, internal/gaurd/, internal/guard/nope.go and tools/go.mod in a fixture doc, and passes cmd/swarm/main.go, go.mod, go.sum, internal/guard/ and internal/. It passes on the real docs of main with ship-gates merged, with tests/doc_check_known.txt still empty. On a worktree copy, removing cmd and internal from ROOTS fails the test, removing the go.mod rule fails it, and removing the protected-path rule fails it on the fixture's internal/guard/ and on the real docs.
- scripts/select-tests.sh --run passes

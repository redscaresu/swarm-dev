---
kind: code
status: blocked
epic: first-port
depends_on: [walk-calls]
needs: walk-calls (fileRecord's calls and lits)
touches: [internal/layers/starts_test.go, internal/layers/testdata/starts/]
estimate_lines: 110
---

# A Go check fails a process start that is not an exec.Command or exec.CommandContext call

Needs walk-calls: fileRecord's calls and lits. The rest of tests/timeouts_test.sh's go_check (docs/port/tests.tsv:147). go-check-deadlines judges exec.Command and exec.CommandContext calls, so this check fails every other way to start a process (rules.md: scope a check to the whole class). It is split from go-check-deadlines to keep each under the 200-line cap on a check. internal/layers/ is protected, so merge holds the PR for the user.
- A new file internal/layers/starts_test.go, with testdata/starts/bad and testdata/starts/clean, in time_test.go's pattern.
- It covers every non-test .go file of the module, adapters included. It fails os.StartProcess, syscall.Exec, syscall.ForkExec and syscall.StartProcess calls; an exec.Cmd composite literal, with or without &; exec.Command or exec.CommandContext used as a value (a selector record with called false); and a dot import of os, os/exec or syscall. exec.Cmd as a type, in a signature or a var, passes.
- No comment lets one through. A later port that needs one edits this check.
- Every top-level name in the file starts with start.
- TestRealTreeStarts logs the rule, and fails unless the walk finds cmd/swarm/bridge.go:36's exec.Command call, so a walk that read nothing cannot pass.
- No AGENTS.md change, as in go-check-regexp.

**Done when:**
- (1) TestStartsFixtures asserts the exact finding lines on testdata/starts/bad: os.StartProcess, syscall.Exec, syscall.ForkExec, an exec.Cmd literal and &exec.Cmd{}, exec.Command passed as a value, a Cmd literal of an aliased os/exec, and a dot import of os/exec in internal/adapter/herdr/. It asserts none on testdata/starts/clean: exec.Command and exec.CommandContext calls, and *exec.Cmd as a parameter type. (2) TestRealTreeStarts passes and logs cmd/swarm/bridge.go:36. (3) On a copy of the worktree without .git, each of these turns a test red, and the FAIL lines are in the PR body: syscall left unjudged; composite literals left unjudged; a value use accepted; the real tree's exec.Command call dropped. (4) gofmt -l . prints nothing, and go vet ./... and go test ./... pass. (5) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

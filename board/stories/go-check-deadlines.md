---
kind: code
status: blocked
epic: first-port
depends_on: [walk-calls]
needs: walk-calls (fileRecord's calls with their arguments and the function around each, its comments, and constValue)
touches: [internal/layers/deadline_test.go, internal/layers/testdata/deadline/]
estimate_lines: 200
---

# A Go check fails a gh, herdr or curl start that has no deadline made where it starts

Needs walk-calls: fileRecord's calls with their arguments and the function around each, its comments, and constValue. The go_check of docs/port/tests.tsv:147 for tests/timeouts_test.sh, which stays and keeps scanning the bash. internal/layers/ is protected, so merge holds the PR for the user.
- A new file internal/layers/deadline_test.go, with testdata/deadline/bad and testdata/deadline/clean, in time_test.go's pattern.
- It judges every exec.Command and exec.CommandContext call in the module's non-test .go files. go-check-starts fails every other way to start a process, so nothing goes around this check.
- The program (Command's first argument, CommandContext's second) must be a string literal or a module constant, told by its last path element. Any other program fails, since the check cannot tell what it runs.
- A start needs a deadline when its program is gh, herdr or curl; a wrapper that runs the next argument (env, nohup, time, command, exec, nice, xargs), since the bash check sees a call behind those (tests/timeouts_test.sh:4-5); or sh, bash, zsh or dash with a literal -c argument. cmd/swarm/bridge.go:36 runs bash with a script path and no -c, so it needs none.
- Such a start passes only as exec.CommandContext whose context argument is an identifier that its own function (the call record's function) sets once, as the first name on the left of := from context.WithTimeout or context.WithDeadline, sets nowhere else, and has as no parameter. So exec.Command fails, and so do context.Background(), a parameter, context.WithoutCancel(ctx), a context set again after, an inner := that shadows it, and a WithTimeout context made while another is passed.
- A dot import of os/exec or context fails. An aliased import counts through its path, in an adapter too: internal/adapter/ is where the gh and herdr starts will live, and the import checks exempt adapters (internal/layers/imports_test.go:65).
- A line that is right says so with a trailing `// no-timeout: <reason>`, as in the bash. No reason, no pass.
- Go is stricter than the bash, which bounds only the calls that can wait forever (tests/timeouts_test.sh:2-6). In Go every such start has its deadline where it starts, which binds the gh and herdr adapters to come. TestRealTreeDeadline logs that rule, and each finding names the fix.
- Every top-level name in the file starts with deadline.
- TestRealTreeDeadline fails when the walk finds no exec.Command or exec.CommandContext call, and asserts cmd/swarm/bridge.go:36 is among those found, judged as needing none.
- No AGENTS.md change, as in go-check-regexp.

**Done when:**
- (1) TestDeadlineFixtures asserts the exact finding lines on testdata/deadline/bad: exec.Command of gh, of /usr/bin/curl and of a const naming herdr; exec.CommandContext under context.Background(), under a parameter, under context.WithoutCancel(ctx), under a context set again after WithTimeout, under one shadowed by an inner :=, and under another context while a WithTimeout one is made; a program from a variable; exec.Command of env with gh; bash -c with a gh script; an aliased os/exec; a dot import of os/exec in internal/adapter/gh/; and the comment with no reason. It asserts none on testdata/deadline/clean: CommandContext under WithTimeout made from a parameter context, and under WithDeadline; exec.Command of bash with a script path; the comment with its reason. (2) TestRealTreeDeadline passes and logs cmd/swarm/bridge.go:36. (3) On a copy of the worktree without .git, each of these turns a test red, and the FAIL lines are in the PR body: exec.Command of gh accepted; any context accepted; a function that calls WithTimeout anywhere accepted; a program from a variable accepted; the wrappers and -c left unjudged; the comment accepted with no reason; the real tree's starts dropped. (4) gofmt -l . prints nothing, and go vet ./... and go test ./... pass. (5) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

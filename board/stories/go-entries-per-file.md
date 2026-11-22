---
kind: code
status: later
epic: helpers-shared
depends_on: []
touches: [cmd/swarm/frame.go:entries, cmd/swarm/frame_test.go:TestRegister, docs/port/README.md:§ Two forms, AGENTS.md:§ Working on this repository]
estimate_lines: 110
---

# Each entry of the binary's table registers from its own file

Every entry is one line of one map literal (cmd/swarm/frame.go:121-125). The five entries this epic adds, and every later port's, would all edit those lines. The table becomes a map that a register function fills, called from each entry's own file (an init there); register panics on a name it already holds. wrapper-fixture and _wrapper-fixture register as they do now. TestTableMatchesMarkers keeps checking the table against bin/ported/. docs/port/README.md § Two forms says how bash inside a command runs a `_` entry: `binary_run _<name>` (bin/lib/binary.sh:263-286), a subshell that execs the binary with the frame handed over. That is one process start, as python3's was, and no nested swarm.sh. AGENTS.md's layout block (AGENTS.md:170-177) says 'the store's two methods' and, unless first-port changed it, 'no command is ported yet'; this epic's stories make both false, and the block names none of the packages they add. This story is the epic's one AGENTS.md edit: the store's methods with no count, the table as entries that register from their own files, and one line for internal/'s rules packages by rule (each a bin/lib helper or a command moved to Go, named for it), not a list. If first-port's merged port PR already settled the table or the call, follow it; the lead closes this story once both hold on main.

**Done when:**
- (1) A Go test registers a second entry under a name the table holds and sees register panic. It goes red when the duplicate check is removed, shown on a worktree copy without .git. (2) TestTableMatchesMarkers and tests/binary_dispatch_test.sh pass unchanged. (3) docs/port/README.md § Two forms names `binary_run _<name>` as bash's call from inside a command, and says it is a subshell that execs the binary. (4) AGENTS.md's layout block gives no count of the store's methods and does not say no command is ported, and tests/doc_check_test.sh passes. (5) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

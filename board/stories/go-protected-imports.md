---
kind: code
status: blocked
epic: go-layers
depends_on: [go-interfaces, go-layer-walk, go-clock]
needs: go-interfaces (internal/iface on the short list, and classify); go-layer-walk (the walk's records in internal/layers/walk_test.go); go-clock (internal/clock on the short list)
touches: [internal/layers/protected_test.go, internal/layers/testdata/protected/]
estimate_lines: 120
risk: high
---

# Fail a protected Go package that imports a module package outside the four and a short list

Uses classify and internal/iface from go-interfaces, the walk's records in internal/layers/walk_test.go from go-layer-walk (which it does not edit), and internal/clock from go-clock. risk: high because it is the check that keeps guard, merge, release and agent-environment rules inside the paths the user merges. The protected packages are internal/guard/, internal/merge/, internal/release/ and internal/agentenv/, matched as a prefix with its trailing slash, as OWN_PROTECTED does (bin/lib/board.sh:2514), so internal/merge/x is covered and internal/guardian/ is not. A comment names OWN_PROTECTED as the source: ship-gates fixed the four. The rule: a non-test file in one fails when it imports a module package that is not under one of the four, internal/iface (the interfaces and the store's types) or internal/clock. Standard imports are go-layer-walk's to judge. The test logs the four, the short list, and the protected packages that exist; on today's tree it says none exists yet. The red proof's tmp/ PR touches internal/merge/, so swarm.sh merge holds it; close it unmerged. Fixtures follow go-layer-walk's limits. Break: add internal/board to the short list; the fixture test must go red.

**Done when:**
- For fixture trees under internal/layers/testdata/protected/: internal/merge/x importing internal/board fails, naming file:line and the short list. internal/guard importing internal/iface, internal/clock, internal/release and the standard library passes. internal/guardian importing internal/board is not flagged by this rule. On the real tree it passes and logs that no protected package exists yet. It fails when a short-list entry is not a package in the tree. A throwaway tmp/ branch PR with internal/merge/x.go importing a rules package turns go-checks red, and is closed unmerged. The story PR links it. tests/port_swarm_names_test.sh and tests/port_locks_test.sh pass.
- scripts/select-tests.sh --run passes

---
kind: code
status: ready
epic: binary-fetch
depends_on: []
touches: [bin/lib/binary.sh:binary_find, tests/binary_find_test.sh:no-.git cases]
estimate_lines: 40
easy: true
---

# binary_find returns an installed copy's own binary, so a hook finds the one a swarm.sh call fetched

Needs no other story.
binary_find (bin/lib/binary.sh:16-46): in a root with no .git and SWARMDEV_BIN unset, print <root>/swarm (BINARY_BUILD_PATH) when it is an executable file. Otherwise one line and return 1, as now. Builtins only. It still never downloads or builds (HLD:243).
Update binary_find's own comment (:16-23), not the file header: fetch-download owns that in this wave. Change only the no-.git branch (:38-40), so fetch-attest's block after the function merges cleanly.
port-guard's hook wrapper needs this to find a fetched binary (board/epics/port-guard.md:26). binary_path in an installed copy still takes binary_find's answer.
Tests: tests/binary_find_test.sh's no-.git cases. The case at :113 flips.

**Done when:**
- tests/binary_find_test.sh: in a no-.git root with SWARMDEV_BIN unset, an executable <root>/swarm is printed and it returns 0. A non-executable one, a folder named swarm, and none each give one line and return 1. Its gh and go stubs log no call.
- With SWARMDEV_BIN set, its file still wins over <root>/swarm.
- Mutation on a copy, FAIL line quoted: the new branch removed turns the executable case red.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

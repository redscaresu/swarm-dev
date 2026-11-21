---
kind: code
status: ready
epic: binary-wrapper
depends_on: []
touches: [bin/lib/binary.sh:binary_find (new file), tests/binary_find_test.sh (new), docs/port/tests.tsv:binary_find_test row]
estimate_lines: 130
---

# bin/lib/binary.sh: a find-only binary lookup that never builds or downloads

Needs no other story. New bin/lib/binary.sh, sourceable on its own by a hook (it needs no other lib, sets no option, starts no process when sourced) and later by swarm.sh. binary_find <plugin root> takes the root as its argument (a hook passes its own, swarm.sh passes SWARM_HOME) and reads no SWARM_ variable, so bin/lib/binary.sh names no SWARM_ name and docs/port/swarm-names.tsv does not change (tests/port_swarm_names_test.sh:28-33 scans bin/). It prints the binary's path or says there is none, and never builds or downloads. With SWARMDEV_BIN set it uses that file and nothing else: an unusable one is an error, never a fall-through. Unset, in a git checkout (the plugin root has .git, a dir or a worktree's file; the installed copy has none, as ~/.claude/plugins/cache/swarm-dev/swarm-dev/0.31.2 shows), it takes the checkout's build path when a file is there. It does not check staleness; checkout-build adds that for swarm.sh. Define the build path here as a constant: ignored by git and outside bin/, since several tests scan bin/ (tests/port_swarm_names_test.sh:33). Otherwise there is no binary: binary-fetch adds the plugin folder's file and the download. Bash 3.2, shellcheck clean; bin/lib/*.sh is already in the shellcheck list and the test map's reach row (scripts/test-map.tsv:29). The test sources the file, so add its row to docs/port/tests.tsv.

**Done when:**
- With SWARMDEV_BIN naming an executable file, binary_find prints that path and exits 0. Naming a missing or non-executable file, it prints one line naming SWARMDEV_BIN and the path, exits 1, and looks nowhere else.
- Unset, in a git checkout with an executable at the build path, it prints that path. With no file there, and in a copy with no .git, it prints one line saying there is no binary and exits 1.
- Every case runs with gh and go stubs first on PATH that log any call and exit 1; both logs stay empty.
- tests/port_tests_list_test.sh passes with the new row.
- tests/port_swarm_names_test.sh passes with no row changed.
- Mutation: make the unset branch call go (or fall through to the build path when SWARMDEV_BIN names a missing file) and the matching check goes red.
- scripts/select-tests.sh --run passes

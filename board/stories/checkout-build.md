---
kind: code
status: blocked
epic: binary-wrapper
depends_on: [binary-find, marker-dispatch, make-test-binary]
needs: binary-find: binary_find and its build-path constant in bin/lib/binary.sh; marker-dispatch: binary_run in bin/lib/binary.sh, whose lookup call becomes binary_path, and macos.yml's SUBSET line it adds to; make-test-binary: setup-go on every CI test shard (.github/workflows/ci.yml test-shard), which the build test needs
touches: [bin/lib/binary.sh:binary_path, bin/lib/binary.sh:binary_run lookup call, .gitignore:Go build outputs, tests/binary_build_test.sh (new), docs/port/tests.tsv:binary_build_test row, .github/workflows/macos.yml:SUBSET]
estimate_lines: 200
---

# A git checkout builds the binary from source, and again when a Go file is newer

Uses binary-find's binary_find and build-path constant, marker-dispatch's binary_run, and make-test-binary's setup-go on CI. Add binary_path to bin/lib/binary.sh: binary_find first. Then, with SWARMDEV_BIN unset and the plugin root a git checkout, build ./cmd/swarm into the build path when there is no file there, or when a .go file under cmd/ or internal/ (when it exists), go.mod or go.sum is newer (find -newer ... -print -quit, which BSD and GNU both take). Never search the whole root: .swarm/ holds 501 MB in the lead's checkout (critic). Build to a temp file beside it, then rename, so calls started together never run half a file. With no go on PATH, stop with one line saying the checkout needs Go to build the ported command; never run old bash for it. A failed rebuild exits non-zero with Go's error and leaves the old binary in place, unrun (codex). binary_run calls binary_path in place of binary_find. Hooks keep binary_find, which never builds. This runs only for a marked command, so no other command starts a find. Add the build path to .gitignore if it is not ignored yet (.gitignore:15-17 ignore /swarm and /dist/). The test replaces main.go in its own copy, so it does not depend on the real Go. Add its row to docs/port/tests.tsv if it reaches inside, and add it to macos.yml's SUBSET so BSD find and bash 3.2 run it. That holds the PR for the user.

**Done when:**
- In a test git checkout (a copy of the tree with git init), its cmd/swarm/main.go printing 'one', a marker for a name, SWARMDEV_BIN unset: the first call builds and prints one. After main.go is rewritten to print 'two' with a newer mtime, the next call prints two. A third call builds nothing: the binary's mtime and inode are unchanged.
- With SWARMDEV_BIN set in that checkout and a newer .go file, nothing builds (a go wrapper logs no call) and the named binary runs.
- A newer file under .swarm/ or docs/ alone builds nothing: the go wrapper logs no call.
- After a build that printed one, main.go rewritten with a syntax error and a newer mtime: the call exits non-zero, prints Go's error, prints no 'one', and the old binary keeps its inode and mtime.
- In a copy with no .git, no build is tried (a go stub that logs and fails records no call) and the call stops with binary_find's line.
- In a checkout with no go on PATH, the call exits 1 with the one line, and the ported command's bash does not run.
- Two calls started together on a missing binary both print the word and exit 0; git status --porcelain in the checkout is empty after.
- tests/port_swarm_names_test.sh passes.
- macos-tests passes on the PR's head with the file in its subset.
- Mutation: drop the newer-than check and the second call's check goes red; run the old binary when the build fails and the syntax-error check goes red.
- scripts/select-tests.sh --run passes

---
kind: code
status: later
epic: helpers-ci-gate
depends_on: [go-store-files, ci-gate-go-pyvalues]
needs: go-store-files (helpers-shared): Store's ReadFile, Glob, IsFile, MkdirAll, WriteAtomic and Remove (internal/iface/iface.go:Store, internal/adapter/store/store.go). ci-gate-go-pyvalues: Dumps and the decoder (internal/merge/pyvalues.go).
touches: [internal/iface/iface.go:Store, internal/adapter/store/store.go:exclusive create, mtime, whole write, empty-folder remove, pid check, internal/adapter/store/store_test.go:those methods, internal/merge/pollcache.go, internal/merge/pollcache_test.go, docs/port/locks.tsv:.swarm/poll-cache rows, docs/port/swarm-names.tsv:SWARM_POLL_CACHE_AGE]
estimate_lines: 290
risk: high
---

# Go that nothing runs: the poll cache's entries on disk in the format Python writes, and the Store methods it needs

Needs go-store-files: Store's file methods. Needs ci-gate-go-pyvalues: Dumps.
Adds poll_cache.py's on-disk format to internal/merge: the key (sha256 of json.dumps([argv, filt]), then .json), entry, took, put, prune and remove (bin/lib/poll_cache.py:26-105), and the file SWARM_POLL_CACHE_AGE names. put's temp file never ends in .json, so no reader takes half of one.
Store gains only what go-store-files lacks and the poll cache and main's wait records need: create a file exclusively with content (the lock's O_CREAT|O_EXCL), a file's modified time, write a file whole with no temp (took), remove an empty folder (main_ci: ci_gate.py:812-815), and whether a pid runs, as ci_gate.py:742-754 has it (another user's counts). internal/adapter/store implements them.
docs/port/locks.tsv gains the row for the adapter's exclusive create, which port_locks_test.sh already finds in Go (tests/port_locks_test.sh:3,190-196). The swarm-names row for SWARM_POLL_CACHE_AGE names the Go file.

**Done when:**
- (1) For a pages argv holding & and ?, a non-ASCII argument and an empty filter, the Go key equals the sha256 of python3's json.dumps([argv, filt]); the PR shows the run. (2) The Go reads an entry poll_cache.py's put wrote (fixture bytes), and poll_cache.py's entry reads one the Go wrote (shown in the PR); an entry older than the max age, or of another form, is not taken. (3) prune removes only entries older than 600 s; took writes the oldest age taken, in whole seconds. (4) Adapter tests on a real temp folder: the exclusive create fails on an existing file and writes the content otherwise; the empty-folder remove leaves a folder that holds a file; the pid check is true for the test's pid and false for an unused one. (5) port_locks_test.sh passes, and fails with the new row removed; port_swarm_names_test.sh passes. (6) Each new test goes red on a worktree copy without .git where its rule is broken; the PR quotes the FAIL lines. (7) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/pollcache_lock.go, internal/merge/pollcache_lock_test.go, internal/merge/reads.go:pages, docs/port/locks.tsv:.swarm/poll-cache rows, docs/port/swarm-names.tsv:SWARM_POLL_CACHE, docs/port/swarm-names.tsv:SWARM_POLL_CACHE_SECONDS]
estimate_lines: 290
risk: high
---

# Go that nothing runs: the poll cache's lock and through, and pages reading through them

Needs core's cache-store and reads.
Adds lock, owner, release, stale, holder and through (bin/lib/poll_cache.py:107-206): the <key>.lock made exclusively and holding the pid, LOCK_PAUSE, a dead owner's lock or one held past the max age released by the next reader, only the taker releasing, and a read stamped with when it started. The lock file and its protocol do not change (P4).
Hooks pages: with SWARM_POLL_CACHE and SWARM_POLL_CACHE_SECONDS set, a kept read stands in for gh's and a read pages accepts is kept (ci_gate.py:46-66); with them unset nothing changes. docs/port/locks.tsv gains a row for each take site port_locks_test.sh finds in this Go. The swarm-names rows for SWARM_POLL_CACHE and SWARM_POLL_CACHE_SECONDS name the Go files.

**Done when:**
- (1) Go tests through a fake Store and clock: a lock with a live owner makes through wait in LOCK_PAUSE steps, then take the entry the holder kept; a dead owner's lock and one older than the max age are taken over; a read slower than the max age is kept with its start time; a read accept refuses is not kept. (2) pages with both settings set takes a kept read and makes no gh call; with SWARM_POLL_CACHE_SECONDS 0 or unset it calls gh. (3) port_locks_test.sh passes, and fails with a new row removed; port_swarm_names_test.sh passes. (4) Each new test goes red on a worktree copy without .git where its rule is broken; the PR quotes the FAIL lines. (5) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

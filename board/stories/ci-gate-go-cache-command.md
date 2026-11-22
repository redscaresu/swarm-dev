---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [cmd/swarm/pollcache.go, bin/ported/_poll-cache, internal/merge/pollcache_cmd.go, internal/merge/pollcache_cmd_test.go, tests/poll_cache_lock_test.sh, docs/port/tests.tsv:tests/poll_cache_lock_test.sh row, scripts/test-map.tsv:internal/merge row]
estimate_lines: 270
risk: high
---

# Go that nothing runs: the poll cache's command form as the binary's _poll-cache, and a test that Python and Go wait on each other's lock

Needs parts' cache-lock, and core's gh and entry.
Adds `_poll-cache <dir> <max-age> -- gh <args...>` (bin/lib/poll_cache.py:208-246), registered from cmd/swarm/pollcache.go with needsFrame false and its marker bin/ported/_poll-cache. watch_gh (merge.sh:3465) runs it once the switch moves it. It prints a kept read, or runs gh through the CodeHost and keeps an exit-0 answer; a successful run's stderr goes on to its own. A failed run prints its stdout, then its stderr, and exits as gh did: 127 when gh cannot start, 128+n when signal n killed it. stdout keeps any bytes, as surrogateescape does. Bad usage exits 2 with the entry's usage line; an age of 0 keeps nothing. A command other than gh is bad usage, since the one caller passes gh and the CodeHost runs only gh (contradiction 8).
Adds tests/poll_cache_lock_test.sh for P4 while poll_cache.py is left: Python holds a key's lock while the binary waits on the same read and then takes Python's entry, and the reverse. Its tests.tsv row (py reach); it joins the internal/merge test-map row.

**Done when:**
- (1) tests/poll_cache_lock_test.sh passes both ways, and each goes red on a worktree copy without .git where the Go, or the Python, takes the lock without waiting. (2) It compares the binary with poll_cache.py's command form on one stub gh: a kept read, a run with stderr, a failure (stdout then stderr, the exit code), bad UTF-8 on stdout, no gh on PATH (127) and a gh killed by TERM (143). (3) TestTableMatchesMarkers passes, and fails with bin/ported/_poll-cache removed. (4) port_tests_list_test.sh passes. (5) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

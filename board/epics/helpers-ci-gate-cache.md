---
status: active
agreed: 2026-11-24
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
parent: helpers-ci-gate
depends_on: [foundation-exit, helpers-shared-base, helpers-ci-gate-core]
---

# poll_cache runs as Go beside its Python copy, with the same files and lock

poll_cache's store, lock and `_poll-cache` entry exist as Go, reading and writing the same files under .swarm/ as the Python.

A child of [helpers-ci-gate](helpers-ci-gate.md), split on 2026-11-23. The parent's constraints and its shared rules (L2, the P rules) apply here unchanged.

**Done when:** internal/merge/pollcache.go and pollcache_lock.go read and write .swarm/poll-cache in the Python's format, shown by a Go test over files the Python wrote. `_poll-cache` is registered and has its marker file. tests/poll_cache_lock_test.sh has the bash hold the lock while the Go waits, and the reverse, and fails if either side skips the lock. docs/port/locks.tsv and swarm-names.tsv carry the rows the stories name. tests/poll_cache_lock_test.sh also compares `_poll-cache` with poll_cache.py's command form on output and exit code, and goes red when either side alone is changed.

**Stories:**
- [ci-gate-go-cache-lock](../stories/ci-gate-go-cache-lock.md)
- [ci-gate-go-cache-store](../stories/ci-gate-go-cache-store.md)
- [ci-gate-go-cache-command](../stories/ci-gate-go-cache-command.md)

**Out of scope:**
- Switching any bash caller to the Go (helpers-ci-gate-switch)

**Your part:**
- You merge every port here (protected merge package). The carve-out covers every story, as in the parent.

**Areas:**
- ci-gate-go-cache-lock: [internal/merge/pollcache_lock.go, internal/merge/pollcache_lock_test.go, internal/merge/reads.go:pages, docs/port/locks.tsv:.swarm/poll-cache rows, docs/port/swarm-names.tsv:SWARM_POLL_CACHE, docs/port/swarm-names.tsv:SWARM_POLL_CACHE_SECONDS]
- ci-gate-go-cache-store: [internal/iface/iface.go:Store, internal/adapter/store/store.go:exclusive create, mtime, whole write, empty-folder remove, pid check, internal/adapter/store/store_test.go:those methods, internal/merge/pollcache.go, internal/merge/pollcache_test.go, docs/port/locks.tsv:.swarm/poll-cache rows, docs/port/swarm-names.tsv:SWARM_POLL_CACHE_AGE]
- ci-gate-go-cache-command: [cmd/swarm/pollcache.go, bin/ported/_poll-cache, internal/merge/pollcache_cmd.go, internal/merge/pollcache_cmd_test.go, tests/poll_cache_lock_test.sh, docs/port/tests.tsv:tests/poll_cache_lock_test.sh row, scripts/test-map.tsv:internal/merge row]

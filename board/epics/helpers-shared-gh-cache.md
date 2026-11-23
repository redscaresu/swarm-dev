---
status: later
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
parent: helpers-shared
depends_on: [foundation-exit, helpers-shared-base, helpers-shared-report]
---

# gh_cache runs as Go, and the patch gate's cache calls the binary

gh_cache's files and records and report's merged listing exist as Go. The patch gate's cache site in board.sh calls the binary.

A child of [helpers-shared](helpers-shared.md), split on 2026-11-23. The parent's constraints and its shared rules (L2, the P rules) apply here unchanged.

**Done when:** internal/ghcache has comparison tests for files, listing and records, and internal/report for merged. Each fails when either side alone is changed. bin/lib/board.sh's non_fix_cache runs `_non-fix-cache`, and the patch gate's cache keeps its key and its files. A test shows an old session's bash and the binary read each other's entries. The differential run is clean for fx_gate_next_cached and fx_gate_next_cached_empty.

**Stories:**
- [go-gh-cache-files](../stories/go-gh-cache-files.md)
- [go-gh-cache-records](../stories/go-gh-cache-records.md)
- [go-report-merged](../stories/go-report-merged.md)
- [non-fix-cache-binary](../stories/non-fix-cache-binary.md)

**Out of scope:**
- Deleting gh_cache.py, which goes when report.py's copy does

**Your part:**
- Carve-out (HLD:480-485): non-fix-cache-binary swaps the patch gate's cache site. You clear it on this board PR.

**Areas:**
- go-gh-cache-files: [internal/ghcache/files.go, internal/ghcache/listing.go, internal/ghcache/compare_test.go, docs/port/swarm-names.tsv:SWARM_GH_CACHE row, docs/port/swarm-names.tsv:SWARM_GH_FRESH row]
- go-gh-cache-records: [internal/ghcache/records.go, internal/ghcache/records_compare_test.go]
- go-report-merged: [internal/report/merged.go, internal/report/merged_compare_test.go]
- non-fix-cache-binary: [internal/ghcache/nonfix.go, internal/ghcache/nonfix_test.go, cmd/swarm/non_fix_cache.go, bin/ported/_non-fix-cache, bin/lib/board.sh:non_fix_cache, docs/port/sites.tsv:non_fix_cache row, docs/port/copies.tsv:non_fix_cache row, tests/diff_fixtures_release_gates.sh:fx_gate_next_cached, tests/diff_fixtures_release_gates.sh:fx_gate_next_cached_empty, tests/non_fix_cache_test.sh, tests/speed_list.txt:gate_next_cached line, scripts/test-map.tsv:non_fix_cache row]

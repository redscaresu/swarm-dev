---
kind: code
status: later
epic: helpers-shared
depends_on: [go-gh-cache-files, go-store-files]
needs: go-gh-cache-files: ghcache.Get, Put and Path. go-store-files: Store.Glob and Remove.
touches: [internal/ghcache/records.go, internal/ghcache/records_compare_test.go]
estimate_lines: 220
---

# gh_cache's record helpers run as Go: cached, pull, commits and forget

Needs Get, Put and Path from go-gh-cache-files, and Glob and Remove from go-store-files. internal/ghcache, as bin/lib/gh_cache.py:40-89 has it. Cached gives the cached record when done says it is finished, else fetch's answer, kept once finished. Closed, Merged. Pull is cached once merged, keeping only state, merged_at, updated_at and the head and base refs, in that key order. AsOf. Forget removes a kind's records kept under another updated_at; it takes the folder from files.go's Root (gh_cache.py:73 reads SWARM_GH_CACHE), so records.go names no SWARM_ variable. Commits slurps the pages, is cached while the PR is closed, and keeps each commit's sha and message alone. The caller passes gh as a function. flow_ci_health and flow_merge_ins import these (bin/lib/flow_ci_health.py:10, bin/lib/flow_merge_ins.py:22). A comparison test runs gh_cache.py and the Go with one scripted gh function over one cache folder: written files byte-equal, Forget's removals equal, a damaged record fetched again, a reopened PR, an answer that is no dict, and tests/gh_cache_test.sh's PRs and runs (a run still running until its done file exists, a PR closed without a merge, a merged PR gh lists no runs for).

**Done when:**
- (1) The comparison test passes, files byte for byte. (2) It goes red when Pull alone caches a closed, unmerged PR, when Forget alone removes the newest key, and when gh_cache.py's commits alone keeps a third field, each shown on a worktree copy without .git. (3) tests/port_swarm_names_test.sh passes. (4) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: code
status: later
epic: helpers-shared
depends_on: [shared-gh-cache-call, go-py-json, go-store-files]
needs: shared-gh-cache-call: the user's You: step (1), which says whether this is a sixth module under the comparison test or a bridge. go-py-json: pyjson.Encode and pyjson.Decode. go-store-files: Store.ReadFile, MkdirAll and WriteAtomic.
touches: [internal/ghcache/files.go, internal/ghcache/listing.go, internal/ghcache/compare_test.go, docs/port/swarm-names.tsv:SWARM_GH_CACHE row, docs/port/swarm-names.tsv:SWARM_GH_FRESH row]
estimate_lines: 300
---

# gh_cache's files and incremental listing run as Go, writing the bytes Python writes

Needs shared-gh-cache-call's You: step (1), Encode and Decode from go-py-json, and ReadFile, MkdirAll and WriteAtomic from go-store-files. internal/ghcache, as bin/lib/gh_cache.py:10-38,91-146 has it: Path (<SWARM_GH_CACHE>/<repo lowercased, / as -->/<name>.json); Get (nil with no cache, under SWARM_GH_FRESH, or for a file that does not read or parse); Put (best effort, a temp file renamed over, nothing written for a value Encode refuses); Day; IsHole; Listing with Since, HoleIn, LeftOut and Save (keep_days through clock.UTCNow; a save that changes nothing writes nothing, compared as json.dumps(sort_keys=True) compares). A comparison test runs gh_cache.py and the Go over one cache folder. Each side's file is byte-equal to the other's and reads back through the other's Get. Listing runs over a fresh start, a valid file, one starting after start, an invalid item, a hole, keep_days dropping items and a save that changes nothing, plus tests/gh_cache_test.sh's cases: a listing cut at its limit (CUT, MCUT), a run still in progress, a closed PR never merged. files.go is the one Go file that names SWARM_GH_CACHE and SWARM_GH_FRESH (Root and Fresh); records.go and nonfix.go take the folder from it. Their rows in docs/port/swarm-names.tsv gain files.go.

**Done when:**
- (1) The comparison test passes, files compared byte for byte. (2) It goes red when Path alone keeps the repo's case, when Save alone writes on no change, and when gh_cache.py's put alone writes with sort_keys, each shown on a worktree copy without .git. (3) tests/port_swarm_names_test.sh passes. (4) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

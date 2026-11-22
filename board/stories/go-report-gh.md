---
kind: code
status: later
epic: helpers-shared
depends_on: [go-py-json, go-py-decode]
needs: go-py-json: pyjson.Decode (key order kept). go-py-decode: pytext.DecodeReplace.
touches: [internal/iface/iface.go:CodeHost, internal/adapter/gh/gh.go:Run, internal/adapter/gh/gh_test.go, internal/report/gh.go, internal/report/gh_compare_test.go]
estimate_lines: 300
---

# report's gh runner runs as Go through the code host: gh with its retry and limit, and search_merged

Needs Decode from go-py-json and DecodeReplace from go-py-decode. iface.CodeHost is empty (internal/iface/iface.go:15). Add the one method this needs: run gh with arguments and a time bound, giving the exit code, stdout and stderr, and a result of its own when the bound passes. The gh adapter's Run (internal/adapter/gh/gh.go) runs gh from PATH and kills it at the bound. internal/report, as bin/lib/report.py:175-239,278-286 has it: GHSeconds, GHLimit, Passes, Spent, and a GH value holding Error and Limit, which one run shares as report.py's globals do. GH.Call builds the call text; retries a reset or a 5xx after 1 s and then 2 s, through clock's scaled sleep; makes no call once the hourly limit is spent; reads JSON as strict UTF-8 and other output with replacement; turns CRLF into LF. SearchMerged. A comparison test runs report.py's gh and search_merged and the Go against one scripted gh stub on PATH: JSON, not JSON, bad UTF-8, exit 1 with stderr, a 502 then JSON, a reset three times, the rate limit then another call, a sleep past a short bound. It compares the result, Error and Limit byte for byte, with SWARM_SLEEP_SCALE small. Other stage-2 epics may add CodeHost methods: see contradictions.

**Done when:**
- (1) The comparison test passes. (2) It goes red when GH alone retries a 404, when it alone calls gh once the limit is spent, and when report.py's gh alone keeps CR, each shown on a worktree copy without .git. (3) The adapter's test shows a gh that outlives the bound is killed. (4) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: code
status: later
epic: helpers-shared
depends_on: []
touches: [internal/pyjson/json.go, internal/pyjson/compare_test.go]
estimate_lines: 170
---

# Go writes and reads JSON as Python's json module does

Old sessions write .swarm/gh-cache with json.dump (bin/lib/gh_cache.py:33), and the differential run compares the files a command writes, so the Go must write the same bytes. internal/pyjson: Encode as json.dump writes (', ' and ': ' separators; ensure_ascii escapes with Python's short forms and surrogate pairs above U+FFFF; object keys in the value's own order; ints as ints); Decode keeping key order and ints, taking what json.loads takes (NaN, Infinity, a repeated key whose last value wins) and refusing what it refuses (trailing data). Encode refuses a float that is not a whole number, which no cache record holds. gh_cache, report's log and gh readers and resend's herdr list use it. A comparison test runs json.dumps and json.loads and the Go over the same values and texts, byte for byte: every control character, quote, backslash, /, non-ASCII, an emoji, nested order, empty containers, a repeated key, NaN, trailing data.

**Done when:**
- (1) The comparison test passes. (2) It goes red when Encode alone leaves non-ASCII unescaped, when Decode alone sorts keys, and when Decode alone keeps a repeated key's first value, each shown on a worktree copy without .git. (3) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

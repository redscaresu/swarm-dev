---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/triggers.go, internal/merge/triggers_test.go, internal/merge/testdata/workflows]
estimate_lines: 240
risk: high
---

# Go that nothing runs: the workflow trigger reader on_filters and its Unread refusals

Adds unq, flow, on_filters and Unread (ci_gate.py:19-20, :445-505) to internal/merge. A workflow comes in as text. YAML the Python does not read is Unread in the Go too, never a guess.
Tests use short inline workflow texts, plus this repo's ci.yml and release.yml as testdata. No copy of every workflow: the nine here give only branches: [main], a types list or None, so they test little.

**Done when:**
- (1) Cases for each form on_filters reads: on: push; on: [push, pull_request]; a block of events with a block list, a [flow] list, {}, null and ~ values, comments, and the keys "on", 'on' and true; an absent event (None); types. Each want is ci_gate.py's on_filters on the same text; the PR shows the python3 run. (2) One Unread case per raise site, each message equal to Python's: an anchor and an alias (:450), a {flow} mapping and a [list] over lines (:456), a quoted entry holding a comma (:458), no on: key (:467), an event value it cannot read (:490), and a block line it cannot read (:503). (3) Each case goes red on a worktree copy without .git where its rule is broken; the PR quotes the FAIL lines. (4) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

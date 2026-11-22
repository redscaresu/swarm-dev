---
kind: code
status: later
epic: helpers-shared
depends_on: [go-events-outcome, go-store-files, go-py-json, go-py-decode, go-entries-per-file]
needs: go-events-outcome: eventsoutcome.Outcome. go-store-files: Store.Glob, ReadFile and Remove. go-py-json: pyjson.Decode. go-py-decode: pytext.DecodeReplace. go-entries-per-file: the register call for the entry's own file.
touches: [internal/resend/rows.go, internal/resend/rows_test.go, cmd/swarm/resend_rows.go, bin/ported/_resend-rows]
estimate_lines: 280
---

# resend_pass's row program runs as Go, as the binary's _resend-rows entry, not yet called

Needs Outcome from go-events-outcome; Glob, ReadFile and Remove from go-store-files; Decode from go-py-json; DecodeReplace from go-py-decode; register from go-entries-per-file. resend_pass's inline program (bin/lib/lifecycle.sh:4838-4911) is about 70 lines, so swapping its call means porting it whole. A rules package internal/resend takes the herdr agent list (stdin, read as json.loads reads it), events.tsv, the resent file, the own panes, the backlog conductor's name, AGENT_NAME_MAX and the briefs folder. Its agent name rule is the program's own, per byte (:4844-4846: bytes lower-cased, any other byte a dash, s before a name that starts with no letter, cut at AGENT_NAME_MAX), not report.AgentName. It prints the rows the program prints, in its order and with its fields, and removes the .unsent markers it removes (agent gone, working, blocked or done; a failed removal ignored). Where the program fails as a whole (a list that is not herdr's JSON, a marker that is not UTF-8), the entry fails too, so the caller's `|| return 0` holds. The _resend-rows entry takes these as arguments and stdin, not as SWARM_ variables. Each Go test's expected rows are the inline program's own output on the same fixture, which the PR records with the command that produced them. resend-pass-binary wires the entry in. Marker bin/ported/_resend-rows.

**Done when:**
- (1) Go tests pass for: a new delivery; the after mode; rechecked; a marker kept for an idle agent and removed for a gone, working, blocked and done one; a tell taking its start's role; the backlog conductor; a failed start resetting newest; a 4-column line; a short marker; a non-ASCII agent name. (2) The marker removal, the mode, the tell role and the per-byte name tests each go red when their branch is broken in the Go, shown on a worktree copy without .git. (3) TestTableMatchesMarkers passes with the marker. (4) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

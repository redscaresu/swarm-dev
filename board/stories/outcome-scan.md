---
kind: code
status: blocked
epic: telemetry-readers
depends_on: [outcome-readers-dash, outcome-readers-flow, outcome-readers-lead, outcome-readers-merge, outcome-readers-agents, events-outcome-helper, deferred-reason]
needs: [outcome-readers-dash, outcome-readers-flow, outcome-readers-lead, outcome-readers-merge, outcome-readers-agents: every events outcome read already on the helper, so the scan is green on main, events-outcome-helper: events_outcome.py and EVENT_OUTCOME_AWK, the code the scan exempts, deferred-reason: orders the shared reports.sh:out_of_scope_findings; the scanner reads it after deferred rows land]
touches: [tests/outcome_scan_test.sh (new), scripts/test-map.tsv:bin row floor, bin/lib/reports.sh:out_of_scope_findings (mark), bin/lib/report.py:rework_of (mark), bin/lib/flow_test_runs.py:test-runs read (mark)]
estimate_lines: 180
easy: false
---

# A scanner fails any bin/lib exact compare or slice of the raw outcome column

Needs every wave-2 reader story merged (outcome-readers-dash, -flow, -lead, -merge, -agents): until then the scan is red on main. Needs from events-outcome-helper: the file and function it exempts (events_outcome.py, EVENT_OUTCOME_AWK). New tests/outcome_scan_test.sh, in tests/loose_match_test.sh's pattern: scans every bin/lib/*.sh, bin/lib/*.py and bin/swarm.sh, awk and perl programs and inline python included, and fails naming file:line on an exact compare of the outcome column ($5, $F[4], [4]) with a literal or variable, a slice of it (substr, [n:m]) or an end-anchored match on it, outside the helper. A line ending `# outcome-scan: ok <reason>` is skipped; marks go only on non-events reads: findings.tsv at reports.sh:out_of_scope_findings (98) and report.py:rework_of (166), test-runs.tsv at flow_test_runs.py (41). finding_rule's `$5 == "fixed"` (build.sh:195) is brief text, so the scan skips heredoc text instead of marking it. Adds the test to scripts/test-map.tsv's bin row floor beside loose_match_test.sh. Detection stays under ~200 lines.

The scanner also flags the Python forms that break on a tail: fullmatch, endswith, dict lookup (`.get(f[4])`) and membership (`in`) on the raw outcome column; report.py:64 (findings.tsv) gets a mark. Add the new events_tail_* and events_fixture tests to the bin row's floor in scripts/test-map.tsv, so a change to bin/lib/events_outcome.py selects them.

**Done when:**
- outcome_scan_test.sh passes on main, with marks only on the non-events reads named in scope, each mark naming the file it reads.
- In a copy of bin/lib, each of `$5 == "ok"` in an events awk program, `e[4] == "ok"` in a flow section, `substr($5, 8)` and `$5 ~ /x$/` makes it fail, naming that file:line.
- scripts/select-tests.sh selects outcome_scan_test.sh for a change to any bin/lib/*.sh or bin/lib/*.py.
- A mutation per Python form (==, slice, fullmatch, endswith, .get, in) on a copy of a reader turns the scanner red, and the PR body quotes each FAIL line.
- scripts/test-map.tsv's bin row floor lists every events_tail_* and events_fixture test.

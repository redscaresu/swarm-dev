---
kind: code
status: later
epic: helpers-shared
depends_on: []
touches: [internal/report/doc.go, internal/report/text.go, internal/report/text_compare_test.go]
estimate_lines: 240
---

# report's pure text rules run as Go: pr_key, step-ups, agent names, phases and merge times

internal/report, the package the later report stories add to: PRKey, StepUp, EscalateBuild, AgentNameMax, AgentName, CutRecords, Phases, Control, MergeTime and LocalDay (bin/lib/report.py:8-39,130-140,181). AgentName is report.py's own rule (report.py:26-29): per code point, after Python's lower(), so İ (U+0130) lowers to i and U+0307 and gives two characters, and each other non-ASCII code point gives one dash. CutRecords keys by it. bash's agent_name and resend_pass's inline copy work per byte (bin/swarm.sh:583-588, bin/lib/lifecycle.sh:4844-4846); that rule is go-resend-rows' own, not this one. Prices moves to go-report-logs, whose turns is its one user in report.py. A comparison test runs report.py with python3 -I and the Go over the same inputs, byte for byte: pr_key on a URL, owner/repo#N with spaces, a trailing slash, mixed case and Unicode digits (Python's \d takes them, RE2's does not); agent_name and cut_records on ASCII, é, İ, the Kelvin sign, a name past 32 code points and two names that cut alike; escalate lines; merge_time with Z, an offset, no offset and garbage, using only forms every supported python3 reads alike (fromisoformat widened in 3.11). No Python test calls these functions alone (grep -l over tests/), so these inputs are the malformed cases.

**Done when:**
- (1) The comparison test passes under the python3 on PATH. (2) It goes red when PRKey alone keeps the repo's case, when AgentName alone works per byte, when MergeTime alone accepts a time with no offset, and when report.py's pr_key alone is changed, each shown on a worktree copy without .git. (3) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [intervene-cause]
needs: [intervene-cause: the cause= field and the three-argument form (bin/swarm.sh:intervene)]
touches: [bin/lib/flow_incidents.py:cause and stalled-input tables, tests/incidents_test.sh:flow cause and stall cases, docs/reference-logs.md:incidents paragraph (Flow and features), bin/lib/reports.sh:incidents doc comment]
estimate_lines: 150
easy: false
---

# flow incidents: counts by kind and cause, and stalled incidents with their inputs

From intervene-cause it uses the cause= field intervene writes, for its end-to-end case. bin/lib/flow_incidents.py keeps its `day kind incidents` table and its stops table byte for byte (dash --check reads them) and adds, each after a blank line: `kind cause incidents` over the window (`-` where a line has no cause=); the stalled incidents in the window with bg, test and sign as their fields give them (`-` when absent: not measured, never shown as 0); then one line with stalled incidents having any input 1 and lead-hand plus user-caught lines with cause=false-stall: Goal 3's bar. The input spellings bg=0|1 test=0|1 sign=0|1 are the epic's; stall-inputs writes them and adds its own end-to-end case. Update bin/lib/reports.sh's incidents comment and the incidents paragraph (docs/reference-logs.md:365).

**Done when:**
- tests/incidents_test.sh flow cases: intervene lines written by `swarm.sh intervene` with two causes print in the kind-cause table with their counts; an incident with no cause prints under `-`.
- A fixture stalled incident with bg=1 test=0 sign=0 prints with those values and counts in the any-input-1 total; one with all 0 does not; one with no fields prints `-` and is not counted.
- The false-stall count counts lead-hand and user-caught lines with cause=false-stall only.
- Over the same fixture the `day kind incidents` table is unchanged, and tests/dash_check_test.sh passes.
- Copy-aside proof: reading a missing input as 0 turns the no-fields case red.

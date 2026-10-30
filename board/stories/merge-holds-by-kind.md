---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [events-outcome-helper]
needs: [events-outcome-helper: append_event key=value fields and the outcome()/fields() readers in bin/lib/events_outcome.py (telemetry-readers)]
touches: [bin/lib/merge.sh:merge_fail (hold field), bin/lib/merge.sh:merge_hold, bin/lib/merge.sh:protected_hold, bin/lib/merge.sh:dropped_hold, bin/lib/merge.sh:merge_pr (costs: hold line), bin/lib/flow_merges.py:holds table, tests/merge_rules_test.sh:hold field cases, tests/flow_merges_test.sh (new), docs/reference-logs.md:merges paragraph (Flow and features), docs/reference-logs.md:merge sentence (Logs and outcomes), bin/lib/reports.sh:merges doc comment]
estimate_lines: 200
easy: false
---

# merge's held lines carry hold=<kind>, and flow merges counts holds by kind

Builds on telemetry-readers' contract (append_event's key=value fields, its separator, bin/lib/events_outcome.py outcome() and fields()), merged before this epic starts (the epic's depends_on). Matching hold text would be a heuristic (rules.md: match exact records), so merge's held refusals, written through merge_fail (merge.sh:481), carry hold=dropped-lines (dropped_hold :873 and its unchecked form :886), hold=protected (protected_hold :405, :410) or hold=money (merge_pr's costs: line :1092; merge_hold :389 by what its why names). bin/lib/flow_merges.py keeps its `day finished` table as it is (tests/dash_check_test.sh:68 reads it) and adds, after a blank line, `day dropped_lines protected money unmarked`: held merge lines per local day by hold=, an older held line with no field under unmarked, so a 0 in the three reads as none held. Goal 8's row reads dropped_lines.

pr_held returns the hold's kind (money or unreadable) as a record; merge_hold writes hold= from that record, never by matching its why text (rules.md: match exact records).

**Done when:**
- tests/merge_rules_test.sh hold field cases: a merge held for a protected path, for a costs: line and for dropped base lines each writes a merge line whose fields() give hold=protected, hold=money and hold=dropped-lines; a refusal that is no hold has no hold= field.
- tests/flow_merges_test.sh (new): those three lines print under their columns on their day; an old held line with no field counts under unmarked only.
- The `day finished` table is unchanged over the same fixture and tests/dash_check_test.sh passes.
- Copy-aside proof: dropping the field from dropped_hold turns its case red.
- docs/reference-logs.md's merges paragraph names the table and its merge sentence names hold=; tests/doc_check_test.sh passes.

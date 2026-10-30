---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [events-outcome-helper]
needs: [events-outcome-helper: append_event key=value fields and the outcome()/fields() readers in bin/lib/events_outcome.py (telemetry-readers)]
touches: [bin/lib/flow_start_failures.py (new), tests/flow_start_failures_test.sh (new), tests/flow_sections_test.sh:section lists, docs/reference-logs.md:flow section list (Flow and features), docs/reference-logs.md:start_failures paragraph (new, Flow and features), docs/reference-logs.md:flow row (Commands), bin/lib/reports.sh:start_failures doc comment (new)]
estimate_lines: 180
easy: false
---

# flow start_failures: review agents that did not start, and whether a start followed within 10 minutes

Builds on telemetry-readers' contract (append_event's key=value fields, its separator, bin/lib/events_outcome.py outcome() and fields()), merged before this epic starts (the epic's depends_on). New bin/lib/flow_start_failures.py (flow_report.py runs every flow_*.py, flow_report.py:1-36). A failed start is a review-agent line whose outcome no_review_events already counts as one (lifecycle.sh:3724: `did not start`, `start was unclear`): use the same rule, not a new match. Per local day in the window: failed, restarted_10m (an ok review-agent start for that slug within 10 minutes after it), not_restarted; then, after a blank line, slug and time of each not restarted. With no failed start in the window it prints a line saying so, not a row of zeros. Goal 4's bar reads not_restarted. Add the section to tests/flow_sections_test.sh's two section lists (:28, :37), docs/reference-logs.md's section list (Flow and features, :218) and the flow row (Commands, :717), and bin/lib/reports.sh's flow doc comment.

**Done when:**
- tests/flow_start_failures_test.sh (new), on a fixture events.tsv: a failed start followed by an ok start of the same slug 9 minutes later counts as restarted; one followed at 11 minutes and one never followed count as not restarted; an ok start of another slug does not count.
- A failed start outside --since/--until is not counted; the same fixture with a key=value tail on every row prints the same.
- With no failed start in the window the section prints its no-failures line.
- tests/flow_sections_test.sh passes with start_failures in both lists.
- Copy-aside proof: widening the window to 15 minutes turns the 11-minute case red.
- docs/reference-logs.md lists start_failures with what each column means; tests/doc_check_test.sh passes.
- Tests cover both outcomes, `did not start` and `start was unclear`, repeated attempts for one slug, and a matching ok restart within and after 10 minutes.

---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [events-outcome-helper]
needs: [events-outcome-helper: append_event key=value fields and the outcome()/fields() readers in bin/lib/events_outcome.py (telemetry-readers)]
touches: [bin/swarm.sh:INTERVENE_CAUSES (new), bin/swarm.sh:intervene, bin/swarm.sh:usage intervene line, tests/intervene_test.sh:kind and cause cases, tests/events_test.sh:dispatch arm loop (intervene args), commands/swarm.md:intervene lines, docs/lead-by-hand.md:intervene line, docs/reference-logs.md:intervene sentence (Logs and outcomes), docs/reference-logs.md:intervene row (Commands), AGENTS.md:intervene bullet]
estimate_lines: 130
easy: false
---

# intervene takes a cause from a fixed list: swarm.sh intervene <kind> <cause> "<line>"

Builds on telemetry-readers' contract (append_event's key=value fields, its separator, bin/lib/events_outcome.py outcome() and fields()), merged before this epic starts (the epic's depends_on). INTERVENE_CAUSES beside INTERVENE_KINDS (bin/swarm.sh:537), a line of the same shape the tests read with sed: review-rounds false-stall start-failed gpg-locked panes-open story-gone pr-no-story dropped-lines pr-churn load-or-logs no-conductor flaky-test classifier upgrade stuck-builder red-main reported-early missing-review tell-lost other. The form becomes `swarm.sh intervene <kind> <cause> "<one line>"`; an unknown cause, or the old two-argument form, dies listing the causes and writes nothing. The line keeps outcome `<kind>: <line>` (dash's interventions count reads it) and gains cause=<cause> as a field. Every place that states the form changes in this PR: the usage line (swarm.sh:21), commands/swarm.md:722-724, docs/lead-by-hand.md:7, docs/reference-logs.md:28 and its Commands row (:714), docs/reference-lead.md:695 and :700, AGENTS.md:85, tests/events_test.sh:169's intervene args. hooks/user-caught-reminder.sh:23 is protected and changes in telemetry-hooks; until then its reminder names the old form and intervene's error lists the causes.

Lead decision (2026-10-30): until telemetry-hooks merges (a protected path the user merges), the old two-argument form still works: it writes the line with cause=none and prints a warning listing the causes. telemetry-hooks' PR makes the old form exit 1. docs/reference-lead.md's user-caught paragraph, which quotes the hook's reminder, moves with telemetry-hooks.

**Done when:**
- tests/intervene_test.sh: `intervene lead-hand flaky-test "<line>"` writes one line whose outcome() is `lead-hand: <line>` and whose fields() give cause=flaky-test.
- An unknown cause and the old two-argument form each exit 1, write nothing, and print every cause in INTERVENE_CAUSES, read from swarm.sh by the test.
- tests/events_test.sh's dispatch arm loop still counts intervene as logged (one line).
- commands/swarm.md names each kind in the new form (intervene_test.sh:80-82 updated); tests/doc_check_test.sh and tests/incidents_test.sh pass.
- Copy-aside proof: accepting any cause turns the unknown-cause case red.
- The old two-argument form writes one line with cause=none and prints the causes as a warning; a test pins both.

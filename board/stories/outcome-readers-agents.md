---
kind: code
status: blocked
epic: telemetry-readers
depends_on: [events-outcome-helper, events-fixture]
needs: [events-outcome-helper: events_outcome.outcome() / fields() and SEP (bin/lib/events_outcome.py), EVENT_SEP and the awk outcome(s) text EVENT_OUTCOME_AWK (bin/lib/agents.sh), events-fixture: tests/fixtures/events/v029-sample.tsv and tests/events_tail_helpers.sh (a stand-in project from an events file, its tailed copy, same_output)]
touches: [bin/lib/agents.sh:sign_held, bin/lib/agents.sh:login_incident, bin/lib/agents.sh:findings_told, bin/lib/build.sh:review_rounds, tests/events_tail_agents_test.sh (new)]
estimate_lines: 95
easy: false
---

# agents.sh's and review_rounds' events readers use the helper; the contract over the fixture

Needs from events-outcome-helper: append_event's fields, EVENT_SEP, EVENT_OUTCOME_AWK and events_outcome.outcome() / fields(). Needs from events-fixture: the fixture, the tailed copy and same_output. Puts agents.sh's sign_held (1439), login_incident (1720-1722; delivery-liveness's skip list kept) and findings_told (2575), and build.sh's review_rounds (850-854), on the awk outcome(). Also the contract test over the fixture that the helper story could not run in wave 1: every fixture outcome written through append_event reads back unchanged. New tests/events_tail_agents_test.sh.

**Done when:**
- events_tail_agents_test.sh: over the fixture project and its tailed copy, login_incident, findings_told and review_rounds give the same result for every fixture target, each non-empty or true for at least one target untailed; inline sign-blocked:/sign-clear: incidents (no live log holds one) give the same sign_held.
- Every fixture outcome, written through append_event with `k=v`, reads back through outcome() as the fixture's outcome and through fields() as {k: v}, so no fixture outcome holds the separator.
- Putting one converted read back on a raw $5 / f[4] in a worktree copy without .git (AGENTS.md's mutation rule) turns the new test red; the PR names the read and keeps the FAIL line.
- Each event-dependent reader this story changes has a positive case: non-empty and equal with and without a tail.

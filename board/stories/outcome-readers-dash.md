---
kind: code
status: blocked
epic: telemetry-readers
depends_on: [events-outcome-helper, events-fixture]
needs: [events-outcome-helper: events_outcome.outcome() / fields() and SEP (bin/lib/events_outcome.py), EVENT_SEP and the awk outcome(s) text EVENT_OUTCOME_AWK (bin/lib/agents.sh), events-fixture: tests/fixtures/events/v029-sample.tsv and tests/events_tail_helpers.sh (a stand-in project from an events file, its tailed copy, same_output)]
touches: [bin/lib/dash_age.py:Signs (events read), bin/lib/dash_finished.py:events read, bin/lib/dash_render.py:escalated_at, bin/lib/dash_render.py:Recent, bin/lib/dash_render.py:speedometer, bin/lib/stall.py:sign_time, tests/events_tail_dash_test.sh (new)]
estimate_lines: 110
easy: false
---

# dash's and stall's events readers read the outcome through the helper

Needs from events-outcome-helper: events_outcome.outcome() and SEP. Needs from events-fixture: the fixture, the tailed copy and same_output. Moves every events.tsv outcome read in these files onto outcome(): dash_age.py (Signs :31-38, incl. the STEP_UP fullmatch), dash_finished.py (:23-25), dash_render.py (escalated_at :146-157; Recent :672-689, incl. the text it shows and its run key; speedometer :816-821), stall.py (sign_time :15-19, `f[4] != "ok"`; dash_age and wait --stall read it). Import by bare name (sys.path[0] is bin/lib); add no -I to a caller. New tests/events_tail_dash_test.sh checks what these readers draw; the whole frame is events-tail-check's, since it also crosses lifecycle.sh's no_agent_events.

**Done when:**
- events_tail_dash_test.sh: over the fixture project and its copy with `<SEP>k=v` on every row, stall.py's last_seen, dash_finished.py's lines, and the Recent box, speedometer and escalated marks dash draws are identical, and each is non-empty untailed.
- A Recent line drawn from a tailed row shows the outcome without the tail.
- Putting one converted read back on a raw $5 / f[4] in a worktree copy without .git (AGENTS.md's mutation rule) turns the new test red; the PR names the read and keeps the FAIL line.
- For each reader this story changes: a text reader's output is non-empty and equal with and without a tail; a predicate (one that returns a status and prints nothing) gives the expected success and failure statuses, the same with and without a tail. Synthetic rows fill any case the fixture lacks.

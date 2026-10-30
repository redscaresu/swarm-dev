---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [tell-refusal-state, decline-only-event]
needs: [tell-refusal-state: event_fields and EV_FIELDS in bin/swarm.sh:main, decline-only-event: its decline_only_round check in mark_review's path, which this story reuses for verdict=decline-only, so the two never parse twice]
touches: [bin/swarm.sh:review-agent arm (round field), bin/lib/board.sh:mark_review (verdict, review-finished event), bin/lib/lifecycle.sh:top_rung_story (review-finished event), bin/lib/flow_review_loops.py:verdict column, tests/review_test.sh:verdict cases, tests/ladder_top_rung_test.sh:review-finished case, tests/flow_review_loops_test.sh:verdict cases, docs/reference-logs.md:review sentence (Logs and outcomes), docs/reference-logs.md:review_loops paragraph (Flow and features), bin/lib/reports.sh:review_loops doc comment (end rule)]
estimate_lines: 230
easy: false
---

# review rounds log round= and verdict=, and a review-finished event

From tell-refusal-state it uses event_fields and main's EV_FIELDS. round=<n> from review_round (build.sh:840) goes on review-agent and review-agent:next lines (main's arm, swarm.sh:1080-1082, sets EV_FIELDS). A start has no verdict yet, so verdicts go on a round's end: the review line gets round= and verdict=pass when mark_review (board.sh:2509) succeeds and verdict=held when it dies held:, through event_fields; `review-finished`, target the slug, with round= and verdict=pass, is written by mark_review's --head path (the review agent's pass), and with verdict=held by top_rung_story's hold (lifecycle.sh:1509-1516, the handover to the lead). findings is the existing tell:findings line and decline-only is review-rounds-end's event, so neither is written here. flow_review_loops.py's end column (:173-178) reads verdict= from the loop's review-finished line when there is one, else its rule today.

**Done when:**
- tests/review_test.sh: `review <slug> --head <sha> <url>` writes a review line with round= and verdict=pass and one review-finished line with the same; a review refused held: writes verdict=held and no review-finished line.
- tests/ladder_top_rung_test.sh: a top-rung hold writes review-finished with verdict=held.
- A review-agent --next line's round= equals the N in its `ok (round N)` outcome.
- tests/flow_review_loops_test.sh verdict cases: a loop whose only end signal is a review-finished verdict=held line prints held-for-lead; the existing fixture with no review-finished line prints as before.
- Copy-aside proof: dropping the verdict read from flow_review_loops.py turns the held case red.
- docs/reference-logs.md's review sentence and review_loops paragraph name the fields and the event; tests/doc_check_test.sh passes.
- Round-end events carry round= and verdict= for all four verdicts (pass, findings, decline-only, held), each with a test and counted by flow.

---
kind: code
status: blocked
epic: conductor-hands-off
depends_on: [next-review-round]
needs: [review-loop's next-review-round: the `review-agent <slug>` events.tsv line with `ok (round <n>)` at each round's start; format only, the fixtures write it, so no depends_on]
touches: [bin/lib/reports.sh:outcomes PR read, bin/lib/reports.sh:flow sections comment, bin/lib/outcomes_join.py:time_in_state, bin/lib/flow_time_in_state.py:header and rows, docs/reference.md:time_in_state paragraph, README.md:flow row, tests/time_in_state_test.sh:green_to_review cases, tests/outcomes_test.sh:column header, tests/dataset_test.sh:outcomes fixture, tests/flow_test.sh:time_in_state header]
estimate_lines: 190
easy: false
---

# flow time_in_state gains green_to_review_min per PR

Per PR, green_to_review_min: minutes from when the PR's head went green to the first review round started after it. Review start: the first events.tsv `review-agent <slug>` line whose outcome is `ok (round <n>)`, which review-loop's next-review-round logs at each round's start, at or after the green time. A plain `ok` start line does not count: the review agent now starts at PR open, before green. Green: the end of the last check run on the head, only when every run on that head concluded success, neutral or skipped. The PR data has no conclusions today: reports.sh's outcomes PR read (bin/lib/reports.sh:200-206) joins statusCheckRollup as startedAt/completedAt. Carry each run's conclusion too, and keep outcomes_join.py's CI phase parsing (:58-60) working. A failed run on the head means no green on it; a later head that goes green counts from its own green. Cached records with no conclusion count as unknown, never green. Print it as the last outcomes column, green_to_review_min (review-loop's features.tsv row names it). time_in_state's rows are per epic (bin/lib/flow_time_in_state.py:40-49), so add green_to_review_median and green_to_review_p90 to each epic row and `all`, with median_p90. Document both in docs/reference.md's time_in_state paragraph (:1618-1630), reports.sh's flow comment (:411-415) and README.md's flow row (:114).

**Done when:**
- tests/time_in_state_test.sh: a PR whose review agent started (`ok`) before green, whose head's checks all succeed by 10:00 and whose first `ok (round 1)` line is at 10:12, has green_to_review_min 12; an empty value with no round line. Fails on today's code, which has no such column.
- The same test: a head with a failed check never counts as green, and a later head that goes green at 11:00 with its round at 11:05 gives 5. Fails if conclusions are ignored.
- The same test: time_in_state's header ends `green_to_review_median green_to_review_p90`, and an epic row over PRs at 2, 12 and 30 minutes prints 12 and 30.
- tests/outcomes_test.sh's column header (:82-88) gains green_to_review_min as the last column, and every earlier column keeps its position; tests/dataset_test.sh passes with the new column in outcomes.

---
kind: code
status: blocked
epic: review-rounds-end
depends_on: [decline-only-event, deferred-bar-confirm, events-outcome-helper]
needs: [decline-only-event: the decline-only end in flow_review_loops.py (a decline-only pass adds no round) and the review_loops docs it rewrote, which this story extends with totals, deferred-bar-confirm: the deferred_proved_real bar the user confirmed, written into the features.tsv row, events-outcome-helper: bin/lib/events_outcome.py and the awk outcome(), through which this story reads event outcomes (telemetry-readers)]
touches: [bin/lib/flow_review_loops.py:deferred and four-plus columns (totals), bin/lib/flow_time_in_state.py:review_wait columns, bin/lib/reports.sh:review_loops doc comment (totals), bin/lib/reports.sh:time_in_state doc comment, docs/reference-logs.md:review_loops paragraph (totals), docs/reference-logs.md:time_in_state paragraph, docs/reference-logs.md:flow row, docs/features.tsv:Goal 1 rows, tests/flow_review_loops_test.sh:deferred and four-plus cases, tests/time_in_state_test.sh:review_wait cases]
estimate_lines: 160
easy: false
---

# flow gives Goal 1's readings: deferred, deferred_proved_real, prs_4plus_rounds and review_wait median and p90, with their features.tsv rows

Needs from decline-only-event: flow_review_loops.py, reports.sh's review_loops comment, docs/reference-logs.md's review_loops paragraph and tests/flow_review_loops_test.sh as it left them (decline-only passes add no round, so the round counts here are right). Needs from deferred-bar-confirm: the bar the user confirmed (proposed: under 10% of deferred findings). flow review_loops' totals (bin/lib/flow_review_loops.py:183-187) gain three columns over the totals' PRs: deferred (declined rows with reason deferred, finding_rows with width=8), deferred_proved_real (escaped rows whose text equals a deferred row's text exactly on the same pr_key, never a prefix; printed `<n> of <deferred>`, `-` with no deferred row), and prs_4plus_rounds (the PRs with four or more rounds, `<pct>% (<n> of <prs>)`, `-` with no PR). flow time_in_state (bin/lib/flow_time_in_state.py:42-52) gains review_wait_median and review_wait_p90 over the row's merged PRs that have a review_wait_min, empty with none as green_to_review's are, read from outcomes' existing phase (no edit to outcomes_join.py). Docs: reports.sh's review_loops (:373-379) and time_in_state (:418-) comments, docs/reference-logs.md's review_loops paragraph (:592-), time_in_state paragraph (:452-) and flow row (:717). docs/features.tsv gains three rows naming their reader, each bar in its baseline text as rows 51-68 do: review wait (`flow time_in_state: review_wait_median, review_wait_p90`; 166 and 464 min, v0.29.0; bar median under 60), PRs with four or more rounds (`flow review_loops: totals prs_4plus_rounds`; 43 of 125, 34%, v0.29.0; bar under 15%), deferred findings (`flow review_loops: totals deferred over prs, deferred_proved_real`; unavailable: new in v0.30.0; the confirmed bar). Read events through telemetry-readers' outcome helper. If a telemetry-writers story touching flow_time_in_state.py is on the board, the lead adds a depends_on on it (contradiction 7). Humanizer over the changed docs.

**Done when:**
- tests/flow_review_loops_test.sh over a fixture findings.tsv: two deferred rows on PR A, an escaped row on A with one of their texts exactly, an escaped row on A with a prefix of the other, and an escaped row on PR B with the first text give deferred 2 and deferred_proved_real `1 of 2`; with no deferred row the column is `-`; proven red by matching on a prefix in a worktree copy.
- Same file: of four PRs with 1, 3, 4 and 5 rounds, prs_4plus_rounds is `50% (2 of 4)`.
- tests/time_in_state_test.sh: over fixture rows with review_wait_min 10, 20, 30, 40 and 200 on merged PRs, the all row's review_wait_median is 30 and review_wait_p90 is 200; a row with none leaves both empty.
- tests/features_test.sh passes with the three new rows (each with a metric, a uses entry and a baseline or unavailable:).
- docs/features.tsv's prs_4plus_rounds baseline says the 43-of-125 count was taken before a decline-only pass stopped counting as a round.

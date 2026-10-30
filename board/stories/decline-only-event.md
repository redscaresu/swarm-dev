---
kind: code
status: blocked
epic: review-rounds-end
depends_on: [events-outcome-helper]
needs: [events-outcome-helper: bin/lib/events_outcome.py and the awk outcome(), through which this story reads event outcomes (telemetry-readers)]
touches: [bin/lib/build.sh:decline_only_round (new, beside review_rounds), bin/swarm.sh:decline-only event (main's review arm), bin/lib/flow_review_loops.py:decline-only end, bin/lib/reports.sh:review_loops doc comment, docs/reference-logs.md:audit log (decline-only line), docs/reference-logs.md:review_loops paragraph, docs/reference-merging.md:review row (Commands), tests/events_test.sh:decline-only cases, tests/flow_review_loops_test.sh:decline-only cases]
estimate_lines: 120
easy: false
---

# review --head writes decline-only <slug> ok (round N) when the pass is a decline-only reply

Needs nothing from another story. A helper decline_only_round <slug> <sha> in bin/lib/build.sh beside review_rounds (:849-858) reads review_rounds' `<round> <started>` (no second events parser, and no edit to review_rounds) and prints <started> when started > 0, round > started (a findings round, as review_rounds counts one, came after the newest review-agent or review-agent:next ok line) and .swarm/reviews/<slug>.head equals <sha>; else nothing. main's review arm (bin/swarm.sh:1073, recorded at :1108-1109), after an ok `review <slug> --head <sha> <url>`, records `decline-only <slug> ok (round N)` with N the started round (contradiction 6), just before the review's own ok line, so a reader meets it first; never for a review without --head, a failed review, or a moved head. decline-only is an event, not a command: no dispatch arm, is_command or EV_CMD arm (contradiction 5). flow review_loops (bin/lib/flow_review_loops.py loops(), :53-125, and the ends block, :172-176): a review line that follows a decline-only line of the same build closes no new round (today it adds one with no minutes), and that loop's end is `decline-only`; documented in reports.sh's review_loops comment (:373-379) and docs/reference-logs.md's review_loops paragraph (:592-). Also docs/reference-logs.md § The audit log (the line) and the review row in docs/reference-merging.md:952. Read event outcomes through the helper telemetry-readers lands (its scanner fails an exact $5 or e[4] compare). review_heads reads the PR head with gh, so events_test needs a gh stub that prints <sha>. Humanizer over the changed docs.

**Done when:**
- tests/events_test.sh `decline-only cases`: with events review-agent ok, tell:findings ok and .swarm/reviews/<slug>.head = <sha>, `review <slug> --head <sha> <url>` appends exactly two lines: `decline-only <slug> ok (round 1)` then `review <slug> ok (<url>)`.
- Same file: the review appends no decline-only line when the head file holds another sha, when a review-agent:next ok line came after the tell, when no findings tell came after the review start, and for a review without --head; proven red by making decline_only_round ignore the head file in a worktree copy.
- tests/flow_review_loops_test.sh: a merged PR whose events are review-agent, tell:findings, decline-only, review, merge lists rounds 1 and end decline-only; the same events without the decline-only line still list rounds 2 and end pass.
- A test makes decline_only_round fail, and the review's own ok event line is still written.

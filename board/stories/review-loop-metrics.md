---
kind: code
status: ready
depends_on: []
touches: [bin/lib/flow_review_loops.py (new), bin/lib/flow.sh:review_loops section wiring, tests/flow_review_loops_test.sh (new), docs/reference.md:flow entry]
estimate_lines: 160
easy: false
---

# flow shows what each review round cost and what it bought

On 2026-10-24 review loops ran to round 7 (plan-pr-grant #441), and the stop and escalation rules changed three times in a day. The user wants the metrics to tune them later. review-round-data (#456) gives fixed and declined findings per round and the round where each PR stopped. It does not give time, model or step-ups per round, or which rule ended a loop.

Add a `review_loops` section to `swarm.sh flow`, built from .swarm/events.tsv, .swarm/findings.tsv and the agent records (agents.tsv, which holds a builder's starting model) only, with no gh calls:
- **Per story PR:** one row per round, with the round, the builder's model in that round (from its `escalate` events and the agent records), the minutes from that round's review start to the next findings tell or the merge, the findings fixed and declined, and any step-up (trigger, from and to, ok or failed) in that round.
- **Per story PR, end state:** `pass` (a round with nothing fixed), `merged-after-fixes`, `held-for-lead` (an `escalated` event), or `open`.
- **Totals, for tuning:**
  - median and p90 rounds per PR;
  - total minutes spent in round 3 and later;
  - share of all fixes found in round 1, round 2, round 3 and later, and on the top rung;
  - for builds that stepped up: fixes per round before and after the step-up;
  - failed step-ups.

**Done when:**
- tests/flow_review_loops_test.sh, on fixture events.tsv, findings.tsv and agents.tsv: a PR with 3 rounds on opus, a step-up to fable, then a pass, reports each round's model, minutes and counts, the step-up line, and end state `pass`. A PR with an `escalated` event reports `held-for-lead`. The totals match the fixtures.
- `make test` passes.

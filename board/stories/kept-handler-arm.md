---
kind: code
status: blocked
epic: no-agent-alert
depends_on: [no-agent-rule]
needs: [no-agent-rule: tests/lead_handler_test.sh and its kind list, whose kept gap this story closes]
touches: [commands/swarm.md:wait --lead handler, tests/lead_handler_test.sh:kind list]
estimate_lines: 30
easy: true
---

# The lead's wait --lead handler acts on a kept: line

Uses no-agent-rule's tests/lead_handler_test.sh, which lists `kept` as its one known gap. commands/swarm.md's wait --lead handler (:117-123) has no arm for the `kept: <slug> <PR URL> (not reviewed)` line that lead_queue prints (lifecycle.sh:1808-1809). Add one: review it with `swarm.sh review-agent <slug> <pr>` and, once it passes, run `swarm.sh review <slug> <pr>`; or run `swarm.sh close <slug> --drop` to send it back (keep_build's texts, lifecycle.sh:443-446). Remove the gap from the test's list.

**Done when:**
- tests/lead_handler_test.sh lists `kept` with no exception, and goes red when the kept: arm is removed.
- The humanizer ran over the changed commands/swarm.md prose, and the PR says so.

---
kind: code
status: blocked
epic: no-agent-alert
depends_on: [no-agent-rule]
needs: [no-agent-rule: the one-list, no-gh call-count case in tests/wait_lead_test.sh, which this story extends to the merge items]
touches: [bin/lib/lifecycle.sh:heads_green, bin/lib/lifecycle.sh:lead_queue merge line, bin/lib/lifecycle.sh:lead_heads (new), docs/reference.md:wait --lead paragraph, tests/wait_lead_test.sh:gh call counts]
estimate_lines: 160
easy: false
---

# The 30 s wait --lead poll makes no gh call

Uses no-agent-rule's per-poll call-count test in tests/wait_lead_test.sh. The epic's budget says the poll makes no gh call. Today lead_queue's merge: path calls gh every poll through heads_green (lifecycle.sh:1773-1790, 1824-1828).

Move that read into lead_heads. It runs on a run's first read and then at most once every LEAD_HEADS_EVERY seconds (300; SWARM_LEAD_HEADS_EVERY for tests). It writes each review item's verdict to .swarm/lead/heads, and lead_queue reads only that file. #392's rule stays: a cached head that the fresh re-read finds red leaves LEAD_GREEN. A merge item now wakes the lead up to 5 minutes after its head turns green (30 s today); reference.md says so. merge-holds (v0.29.0) edits the merge: line after this.

**Done when:**
- Stub logs: the polls between two heads passes make no gh call. The heads pass makes the calls today's poll makes, and wait_lead_test's gh.log counts move to the pass without being weakened.
- With SWARM_LEAD_HEADS_EVERY=1, the existing cases pass: a green costs-money review wakes the lead, a red re-run leaves LEAD_GREEN, and a gh error wakes no one.
- A test: a head that turns green wakes the lead on the first heads pass after it, not before.
- reference.md § The lead states the cadence. The humanizer ran over that prose, and the PR says so.

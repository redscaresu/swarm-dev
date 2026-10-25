---
kind: code
status: ready
epic: no-agent-alert
depends_on: []
touches: [bin/lib/flow_lead_queue.py:ENTER kept kind, bin/lib/dash_render.py:lead queue rows kept row, bin/lib/dash.sh:dash_check lead's queue, docs/reference.md:flow lead_queue, tests/lead_queue_wait_test.sh:kept case, tests/dash_needs_you_test.sh:kept row, tests/dash_check_test.sh:kept item]
estimate_lines: 120
easy: false
---

# flow's lead_queue and dash count a kept story as waiting on the lead

This is small-fixes-027.md:16's 'lead_queue keep rule'. Nothing in the repo says what is wrong with it, and this story reads it as follows. flow's lead_queue never counts a kept story: its ENTER (bin/lib/flow_lead_queue.py:14) has no `kept` kind, though keep_build logs `kept <slug> ok (...)` (lifecycle.sh:439). Yet wait --lead wakes the lead for every `kept:` line (lifecycle.sh:1808-1809), whatever merge is set to, and dash draws no kept row.

Make a kept item enter on its `kept` line. It leaves on a later review, finish, drop or reconcile, or on the close --drop that sends it back to ready. dash draws it in the lead's queue (dash_render.py:397-410) with its exit: review it and run `swarm.sh review <slug> <pr>`, or `swarm.sh close <slug> --drop` (keep_build's texts, lifecycle.sh:443-446). dash_check (dash.sh:255-276) matches it. If the lead learns the item meant something else, re-scope this story before it builds.

**Done when:**
- tests/lead_queue_wait_test.sh: a fixture with a `kept` line for a story in review with kept: shows `kept:<slug>` open. The old flow_lead_queue.py shows nothing, so the test fails before the fix. A later review line closes the item.
- tests/dash_needs_you_test.sh: the kept story is a row in the lead's queue, with its exit.
- tests/dash_check_test.sh: dash --check exits 0 with the kept item, and exits 1 naming the lead's queue when its row is removed.
- reference.md's flow lead_queue section names kept items. The humanizer ran over that prose, and the PR says so.

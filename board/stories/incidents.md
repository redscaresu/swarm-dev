---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [fold-reports]
touches: [bin/lib/agents.sh:wait_agent, bin/lib/lifecycle.sh:close_agent, bin/lib/flow_incidents.py (new), docs/features.tsv:incidents row, tests/incidents_test.sh (new)]
easy: false
estimate_lines: 150
---

# swarm.sh logs incident events for waits, logins and idle builders, and flow counts every incident per day by kind

Needs fold-reports' section loader (a new bin/lib/flow_incidents.py); edits wait_agent in bin/lib/agents.sh and close_agent in bin/lib/lifecycle.sh, and logs through record_event (bin/swarm.sh:758). The event is named incident, with result `<kind>: <detail>`. Logged here: wait-timeout (wait_agent times out), login (an agent stopped on Login expired, wait's auth exit) and idle-no-pr (a builder settles idle, or is closed, with its story still ready and no PR). The other three kinds come from their own stories in the same format: pull-failed from reconcile-drops-backup, merge-blocked from merge-guard-hook, codex-limit from fallback-reviewer. flow counts incidents per day by kind, whatever the kind. features.tsv row.

**Done when:**
- tests/incidents_test.sh: each of the three sites, stubbed, writes one incident line of its kind; flow over a fixture events.tsv holding all six kinds on two days prints the right per-day counts.

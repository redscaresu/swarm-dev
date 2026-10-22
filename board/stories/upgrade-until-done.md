---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [upgrade-ended-turn-is-idle, brief-not-sent-twice]
touches: [bin/lib/lifecycle.sh:upgrade_agents, tests/upgrade_test.sh, docs/reference.md:upgrade]
easy: false
estimate_lines: 180
---

# upgrade keeps going until every agent is on the new version, detached from the session that ran it

The 0.25.0 upgrade on 2026-10-22 took five runs over about three hours. Each run exited 0 after moving only some agents, printed "Run swarm.sh upgrade again once the agents named above are idle", and left a person to notice. The first run died with the lead session that started it. The no-epic conductor's handover arrived after a run had already given up, so that run left its builders on the old version.

Needs upgrade-ended-turn-is-idle's upgrade_state (an ended turn is idle) and brief-not-sent-twice's deliver_prompt (an unreadable status is checked, not resent). `swarm.sh upgrade` re-runs itself detached (nohup, its own process group, log at `.swarm/upgrade-<version>.log`) and prints that log's path and its pid, unless `--foreground` is given. One running upgrade per project: a second prints the running one's pid and log and exits 0. It works in rounds until every agent the project started is on the new version, or until SWARM_UPGRADE_WAIT_MS (raise it to 2 hours). Each round picks up a handover that arrived late, asks again a conductor that wrote none, restarts every agent that is idle now, and reads the agent list again, so an agent started meanwhile is moved too. At the end it prints one line per agent (`<name>: <old> -> <new>`, or `<name>: left on <old>: <why>`) and exits 1 if any agent is left. `swarm.sh status` names an upgrade in progress and the agents still on an old version.

**Done when:**
- tests/upgrade_test.sh, with stub herdr and claude: a conductor whose handover appears after the first round is still upgraded with its builders in a later round. An agent busy in round 1 and idle in round 2 is restarted. One busy past the cap is named with its reason, and the exit code is 1. A second `upgrade` while one runs starts nothing and names the running one. Killing the shell that started the upgrade doesn't stop it.
- docs/reference.md's upgrade paragraph says it runs detached until done, and where its log is.

---
kind: code
status: blocked
epic: lead-woken
depends_on: [lead-alerts-wired]
needs: [lead-alerts-wired: reported_lines, empty and called in lead_queue after pr_lines (same part), and reported: being an alert]
touches: [bin/lib/lifecycle.sh:reported_lines, bin/lib/board.sh:agent_work_left count form, tests/wait_lead_test.sh:reported cases, docs/reference.md:the reported row, commands/swarm.md:the reported paragraph]
estimate_lines: 170
easy: false
---

# wait --lead names a conductor that reported with agent work left (reported:)

Needs from lead-alerts-wired: the empty reported_lines that lead_queue calls after pr_lines, and reported: being an alert. Fill it. For each .swarm/conduct-<epic>.report.md (conductor_report, build.sh:1943), print `reported: <epic> (<n> stories still an agent's), exit: swarm.sh conduct <epic>` while agent_work_left <epic> (board.sh:714-739) is true. start_conductor removes an earlier run's report (build.sh:2011-2012), so a report on disk is the newest run's. conduct-backlog.report.md is the backlog's group (agent_work_left -), with exit `swarm.sh conduct --backlog`. n is the number of stories agent_work_left counts. Give agent_work_left a count form that its current callers do not see: they keep its exit status. Board files and events only, no herdr or gh. Docs: a reported bullet in docs/reference.md § The lead, and a commands/swarm.md paragraph: the conductor stopped with work left, and the exit starts a fresh one.

**Done when:**
- tests/wait_lead_test.sh reported cases: a report for epic e prints `reported: e (1 stories still an agent's), exit: swarm.sh conduct e` with a ready story of e, with a blocked story of e not lead-held, and with a review story of e whose review agent owns it, each case on its own.
- False cases print nothing: a report with only a lead-held blocked story; with only a lead story; with no story left; and no report with a ready story.
- A backlog report with a ready story of no epic prints a reported: line whose exit is `swarm.sh conduct --backlog`.
- tests/epic_finish_test.sh passes unchanged (agent_work_left's exit status and the finish: line).
- Removing the blocked arm from the count turns its case red (copy-aside proof).
- A fixture conductor report with three stories still owned by agents, one ready, one blocked on an agent story and one in review, prints the exact count 3 and the exit.

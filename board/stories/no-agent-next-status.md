---
kind: code
status: blocked
epic: no-agent-alert
depends_on: [no-agent-rule, staged-epics-next]
needs: [no-agent-rule: no_agent_lines in bin/lib/lifecycle.sh, which next_step and status_report print, staged-epics-next: its stage arm in bin/lib/board.sh:next_step, beside which the no-agent arm goes, and next-step-arms-check's arm test in tests/next_test.sh, which the new step must pass]
touches: [bin/lib/board.sh:next_step no-agent arm, bin/lib/merge.sh:status_report, commands/swarm.md:next steps no-agent arm, README.md:watching it, docs/reference.md:next steps and status, tests/next_test.sh:no-agent cases]
estimate_lines: 150
easy: false
---

# next and status name a started story with no live agent first

Uses no-agent-rule's no_agent_lines (bin/lib/lifecycle.sh), and staged-epics-next's stage arm in bin/lib/board.sh:next_step together with next-step-arms-check's arm test, which the new step must pass.

next_step (bin/lib/board.sh:195) prints `no-agent <slug>` with the line's exit as its why. It goes after fix-main (:197-205) and before the conductor arms (:206-231), so a running conductor's wait cannot hide it. It stays gh-free, because dash runs next every frame. status_report (bin/lib/merge.sh:1814-1844) prints a `No agent` section first, before Agents, one line per item. Outside herdr it says the check needs herdr. status_report.py stays panes-only (status_report.py:1-33).

commands/swarm.md gets a `no-agent <slug>` arm in the format next-step-arms-check reads ('   - `no-agent'): run the exit the why names. hooks/lead-stop.sh does not change: an unknown step allows the stop (:9-11). Update README.md's Watching it row for status (:109).

**Done when:**
- tests/next_test.sh: with a running conductor and a started ready story whose builder pane is gone, next's first line is `no-agent <slug>` and its why names the exit. With the builder listed, next prints the conductor's wait as today. With main red, fix-main still comes first.
- A test shows status printing the No agent section first, with the line and its exit. It prints no such section when every started story has a live agent.
- The gh stub log shows no gh call from next's no-agent arm. tests/lead_stop_test.sh passes unchanged, and next-step-arms-check's test finds the `no-agent` arm.
- README.md and reference.md's next steps say what the step and the section mean. The humanizer ran over the changed README, reference.md and commands/swarm.md prose, and the PR says so.

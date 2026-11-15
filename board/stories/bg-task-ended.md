---
kind: code
status: blocked
depends_on: [hung-background-task]
needs: [hung-background-task (its launch-age bound in bg_running; this story adds a liveness check beside it in the same function)]
touches: [bin/lib/agents.sh:bg_running ended-task check, tests/bg_running_test.sh:ended-task cases, docs/reference-building.md:stall paragraph (§ Building) ended-task sentence]
estimate_lines: 90
easy: true
---

# A background task whose process has ended stops counting as life

On 2026-11-15, three builders (#826 pane-close-event, #819 review-pane-closes-after-merge, #850 planning-panes-close) sat idle for about 3 hours. Each had ended its turn to wait on a background test run, and the run had already finished: no process was left in the worktree. The completion notice never reached the agent, so it waited for an event that had passed. bg_running (bin/lib/agents.sh) counts a background task as life from its launch entry in the transcript, not from whether its process still runs. So nothing reported a stall, and the lead found them by hand (logged as a false-stall intervention).

Builds on hung-background-task's launch-age bound in bg_running. Add a check beside it: a background task counts as life only while a process of it is still running. Read that from the task's recorded pid, or the process group a test run records, or, when neither is recorded, from any process whose working directory is the agent's worktree. When the agent's turn has ended and no such process is left, the task no longer counts, so the agent reads as stalled. `wait --stall` then nudges it to read the task's result.

**Done when:**
- tests/bg_running_test.sh: a fixture transcript with a background task launched inside the bound whose process has exited (a pid that is gone) makes bg_running fail; the same task with a live process (a sleep the test starts and kills after) makes it succeed
- A test run that is still running keeps counting as life, as today
- The exited-task case goes red with the new check removed, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- docs/reference-building.md's stall paragraph says a background task whose process has ended does not count as life, and names the 2026-11-15 idle builders as why
- scripts/select-tests.sh --run passes

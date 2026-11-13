---
kind: code
status: blocked
epic: deferred-700
depends_on: [prompt-poll-one-ps]
needs: [prompt-poll-one-ps (prompt_lines' session-log read through report.py's session_log and the per-poll ps snapshot; both stories edit prompt_lines (shared touches part))]
touches: [bin/lib/lifecycle.sh:prompt_lines (stop key), bin/lib/session_mtime.py:last_work (split for import), tests/stuck_work_watch_test.sh:session-log touch cases]
estimate_lines: 220
easy: false
---

# A stop is keyed on the agent's newest own work, so the same stop wakes the lead once

Needs from prompt-poll-one-ps: prompt_lines with its session log read through report.py's session_log, which this story's key builds on, and the poll's single ps snapshot. #700 item 4, #618 round-4 findings 1 and 2. (d) prompt_lines keys a stop on the session log's raw mtime (lifecycle.sh:3636-3640), so a write to the log that is not the agent's own work changes the key and wakes the lead again with the same stop. Key it on the newest own-work entry instead: split bin/lib/session_mtime.py so its last_work can be imported, and rewrite the session-log touches in tests/stuck_work_watch_test.sh as own-work entries. (e) While a running wait hides an api-error, keep the old key, so the same api-error does not wake the lead again when the wait ends. Prove each new case fails with the old key restored, on a worktree copy. The existing api-error case (tests/stuck_work_watch_test.sh:241-246) passes today, because the key is overwritten before the suppression (lifecycle.sh:3697-3699).

**Done when:**
- A test (tests/stuck_work_watch_test.sh) shows a session log written to with no new own-work entry does not give a second prompt: line for the same stop, and a new own-work entry does
- A test shows an api-error stop hidden by a running wait gives no second line once the wait ends with no new work
- Both cases go red with the mtime key restored, shown on a worktree copy
- scripts/select-tests.sh --run passes
- A new case changes the candidate key during a suppressed poll and checks the saved key is unchanged; it goes red with the preservation removed, apart from the other mutation.

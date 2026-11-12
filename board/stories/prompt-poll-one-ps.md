---
kind: code
status: ready
epic: deferred-700
depends_on: []
touches: [bin/lib/lifecycle.sh:prompt_lines (ps read, session-log glob), bin/lib/lifecycle.sh:resend_pass (ps reads), bin/lib/lifecycle.sh:poll_ps (new helper), tests/lead_queue_wait_test.sh:ps count case (new)]
estimate_lines: 130
easy: false
---

# One wait --lead poll reads the process list once

#700 item 4, #618 round-2 findings 6 and 7. (b) A poll with a candidate runs ps -A -ww in prompt_lines (bin/lib/lifecycle.sh:3646) and again in resend_pass (:4438, :4467), the third per poll #618 named. prompt_lines reuses resend_pass's first snapshot (:4438) instead of taking its own. Other readers in the same poll (no_agent_lines, pr_lines, main_red_fix) are out of scope, and resend_pass's second ps (:4467) is a deliberate re-check before Enter and stays. Do not edit lead_wake: lead-wait-merge-reread and lead-wait-line-recheck (other epics) edit it; share through a helper the readers call. (c) prompt_lines' candidate python globs the session log itself (:3600-3640); read it through report.py's session_log instead. No change to what a poll reports. Count ps calls with a stub ps on PATH that logs each call, in tests/lead_queue_wait_test.sh; record today's count in the PR body. Prove the count case fails with the per-reader ps calls restored, on a worktree copy. Line numbers in this story were read at de5fa7a5; main has moved since (board.sh cites by about 47 lines, lead_held is now near :933, review_agent_owns near :954): find each by its function name.

**Done when:**
- tests/lead_queue_wait_test.sh: with a stub ps logging each call, one wait --lead poll with a prompt candidate and a resend candidate makes one fewer `ps -A -ww` call than before, and prompt_lines makes none of its own; the PR body quotes both counts
- That case goes red with prompt_lines' own ps call restored, shown on a worktree copy
- prompt_lines' python finds the session log through report.py's session_log, and tests/pane_prompt_test.sh and tests/stuck_work_watch_test.sh pass unchanged
- scripts/select-tests.sh --run passes

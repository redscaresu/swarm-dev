---
kind: code
status: blocked
epic: telemetry-readers
depends_on: [events-outcome-helper, events-fixture]
needs: [events-outcome-helper: events_outcome.outcome() / fields() and SEP (bin/lib/events_outcome.py), EVENT_SEP and the awk outcome(s) text EVENT_OUTCOME_AWK (bin/lib/agents.sh), events-fixture: tests/fixtures/events/v029-sample.tsv and tests/events_tail_helpers.sh (a stand-in project from an events file, its tailed copy, same_output)]
touches: [bin/lib/lifecycle.sh:build_started, bin/lib/lifecycle.sh:stepped_up_since, bin/lib/lifecycle.sh:top_rung_since, bin/lib/lifecycle.sh:user_merges, bin/lib/lifecycle.sh:stuck_lines, bin/lib/lifecycle.sh:sign_blocked_lines, bin/lib/lifecycle.sh:no_agent_events, bin/lib/lifecycle.sh:no_review_events, bin/lib/lifecycle.sh:review_restart_try, bin/lib/lifecycle.sh:resend_pass, tests/events_tail_lead_test.sh (new)]
estimate_lines: 160
easy: false
---

# lifecycle.sh's events readers read the outcome through the helper

Needs from events-outcome-helper: EVENT_OUTCOME_AWK, EVENT_SEP and events_outcome.outcome(). Needs from events-fixture: the fixture, the tailed copy and same_output. Puts every events.tsv outcome read in bin/lib/lifecycle.sh on the helper (10 functions; the epic's 13 line numbers are stale): build_started (1208), stepped_up_since (1270), top_rung_since (1475), user_merges (2915-2917), stuck_lines' perl read (3049-3052; strip at EVENT_SEP), sign_blocked_lines (3382), no_agent_events (3651-3664), no_review_events (3714-3739, incl. `ok (reopened)` and the PR-URL match at 3729-3730), review_restart_try (3779-3785; its `(try N of M)$` anchors break on a tail today), resend_pass's inline python (4281; imports events_outcome under -I with SWARM_LIB first on sys.path, as tests/lib_path_test.sh checks by text). Prefix and contains matches keep their text. New tests/events_tail_lead_test.sh sources bin/lib over a stand-in project.

**Done when:**
- events_tail_lead_test.sh: over the fixture project and its tailed copy, build_started, stepped_up_since, top_rung_since and user_merges print the same for every fixture target, and each is non-empty for at least one target untailed.
- Inline rows for forms no live log holds (`reconcile ok (reopened)`, review-agent:try `(try N of M) started`, review-agent:restart `started (try N of M)`, sign-blocked:/sign-clear: incidents) give the same no_agent_events, no_review_events, review_restart_try and sign_blocked_lines with and without a tail, each non-empty untailed.
- A tailed `tell` ok row counts as told in stuck_lines and as delivered in resend_pass, as the untailed row does.
- tests/lib_path_test.sh passes.
- Putting one converted read back on a raw $5 / f[4] in a worktree copy without .git (AGENTS.md's mutation rule) turns the new test red; the PR names the read and keeps the FAIL line.
- Each event-dependent reader this story changes has a positive case: non-empty and equal with and without a tail.

---
kind: code
status: blocked
epic: deferred-700
depends_on: [prompt-poll-one-ps]
needs: [prompt-poll-one-ps (resend_pass after its ps reads change; both stories edit resend_pass (shared touches part))]
touches: [bin/lib/lifecycle.sh:resend_pass (outcome match, :4413), bin/lib/lifecycle.sh:rung_late, bin/lib/build.sh:start_unclear, tests/unsent_brief_test.sh:unread-reply cases, tests/escalate_ladder_test.sh:rung_late unread cases]
estimate_lines: 80
easy: true
---

# Only herdr's unread reply to the brief counts as a maybe-sent start

Needs from prompt-poll-one-ps: resend_pass as it left it (that story changes its ps reads; this one its outcome match). #700 item 8 (#626, left for the lead; decided here: narrow it). Three matches take any 'could not be read' as a brief that may have gone out: resend_pass's python (bin/lib/lifecycle.sh:4413), rung_late (:935) and start_unclear (bin/lib/build.sh:822-827). Other failures say 'could not be read' about something else, such as 'its pane could not be read' (agents.sh:2693) and 'origin's default branch could not be read' (lifecycle.sh:865, :1212). tell_undelivered (agents.sh:2638-2656) already matches only sent_note's phrase, 'reply to the brief could not be read' (agents.sh:1098-1102); use that phrase in all three (rules.md: match on exact records). findings_told and flow_tell_refusals.py already match narrowly; leave them. Check tests/outcome_scan_test.sh still passes. Prove each new case fails with the broad match restored, on a worktree copy.

**Done when:**
- A test shows start_unclear and rung_late take 'herdr's reply to the brief could not be read' as maybe sent, and not an outcome that says another thing could not be read (e.g. its pane)
- A test (tests/unsent_brief_test.sh) shows the resend pass treats a start whose outcome names another unread thing as not sent
- Each case goes red with the bare 'could not be read' match restored, shown on a worktree copy
- scripts/select-tests.sh --run passes, outcome_scan_test.sh included

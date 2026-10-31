---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [intervene-cause]
needs: [intervene-cause: the three-argument intervene form and INTERVENE_CAUSES (bin/swarm.sh:intervene), hooks-pr-543-decision: its You: step, #543 merged or closed]
touches: [hooks/merge-guard.sh:record, hooks/lead-stop.sh:log, hooks/user-caught-reminder.sh:reminder line, tests/merge_guard_test.sh:incident field cases, tests/lead_stop_test.sh:field cases, tests/user_caught_reminder_test.sh:REMINDER, docs/reference-logs.md:guard incident sentence (Logs and outcomes), docs/reference-lead.md:user-caught paragraph (quotes the reminder), tests/lead_stop_test.sh:run() compares, tests/live_logs_test.sh:hook cases]
estimate_lines: 160
easy: false
risk: high
---

# Hooks: slug=, role= and version= on the guard's and lead-stop's lines, and the reminder's cause form

From intervene-cause it uses the `intervene <kind> <cause> "<line>"` form; from hooks-pr-543-decision, the user's merge or close of #543 (if its story hooks-keep-live-events-clean is on the board, build after it merges: same record()/log() lines). Builds on telemetry-readers' contract (append_event's key=value fields, its separator, bin/lib/events_outcome.py outcome() and fields()), merged before this epic starts (the epic's depends_on); hooks write events.tsv by hand, so they follow its separator themselves. hooks/merge-guard.sh record() (584-595) adds slug= and role= for an agent's call (SWARM_AGENT; role from .swarm/agents.tsv column 2; a 32-character cut name gives no slug=, as incident-slug-role's rule), none from the lead's session, and version= from the plugin's .claude-plugin/plugin.json. hooks/lead-stop.sh log() (68-73) adds role=lead and version=. hooks/user-caught-reminder.sh:23 names the cause form. Safety path: record() runs inside the Blocked handler (merge-guard.sh:614-615): a raise there exits 1, and the wrapper (merge-guard.sh's last lines) then refuses only a call that says merge, so a guard-blocked call (git clean, pkill, cd ;) would go through. Every new read stays inside its try. The one story holding every hook edit (protected path): the user merges it.

Skeptic fixes: any failure in record() never changes the guard's verdict: catch Exception around the field read and the write, not only OSError. The plugin.json path reaches the `python3 -I -c` program as an argument from the shell (it has no __file__). This PR also makes intervene's old two-argument form exit 1, and moves docs/reference-lead.md's user-caught paragraph to the new reminder text.


Folded in from board PR #543 (closed 2026-10-31, the lead's hooks-pr-543-decision): hooks/merge-guard.sh record() and hooks/lead-stop.sh log() must never append to the main checkout's live .swarm/events.tsv when run from a test in a story worktree, which the swarm.sh guard from tests-keep-live-logs-clean (#529) does not cover. One hook PR for the user instead of two.
**Done when:**
- tests/merge_guard_test.sh: a merge blocked in an agent's pane (SWARM_AGENT=review-abc, agents.tsv role review) writes an incident whose fields() give slug=abc role=review and version= equal to plugin.json's; from the lead's session, no slug= or role=.
- The exact $5 compares at merge_guard_test.sh:110, 189, 240, 288 and 300 read outcome() and pass.
- With agents.tsv unreadable and plugin.json missing, a blocked merge and a guard-blocked git clean each still exit 2 and write their incident without those fields.
- tests/lead_stop_test.sh: a lead-stop line carries role=lead and version=.
- tests/user_caught_reminder_test.sh's REMINDER is the new text with the cause form.
- Copy-aside proof: moving the plugin.json read outside its try turns the unreadable case red.
- With plugin.json not JSON, plugin.json without a version, and agents.tsv holding non-UTF-8 bytes, a blocked merge still exits 2 and writes its incident; a test covers each.
- Every tests/lead_stop_test.sh run() compare reads outcome() and passes with role= and version= on the line.
- tests/live_logs_test.sh runs each hook from a story worktree under the guard and shows the main checkout's .swarm/events.tsv is unchanged; with the guard removed, the same test fails.

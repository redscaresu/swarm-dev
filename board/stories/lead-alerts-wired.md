---
kind: code
status: ready
epic: lead-woken
depends_on: []
touches: [bin/lib/lifecycle.sh:lead_wake quiet filter, bin/lib/lifecycle.sh:lead_queue, bin/lib/lifecycle.sh:stuck_lines (new, empty), bin/lib/lifecycle.sh:main_red_lines (new, empty), bin/lib/lifecycle.sh:reported_lines (new, empty), bin/lib/lifecycle.sh:sign_blocked_lines (new, empty), bin/lib/lifecycle.sh:wait_lead header comment, docs/reference.md:wait --lead command row, docs/reference.md:The lead first-read sentence, commands/swarm.md:wait --lead first-read sentence, AGENTS.md:wait --lead bullet, bin/swarm.sh:usage wait --lead line, tests/wait_lead_test.sh:quiet first read cases, docs/method.md:wait --lead line kinds]
estimate_lines: 90
easy: true
---

# wait --lead: a quiet list of non-alert lines, and the four new line producers wired in

Groundwork so this epic's four new wait --lead lines build in parallel without sharing a part. (1) lead_wake's quiet first read (bin/lib/lifecycle.sh:3813-3816) names ten alert prefixes inline, so a new line is silent on a first read until someone adds it there. Turn the test round: one list, LEAD_QUIET, of the lines another command already shows (held:, escalated:, kept:, merge:, idle:), and every other line is an alert. Today's output is unchanged: those five are exactly the lines lead_queue and lead_wake print that are not in the alert list now. The comments at lifecycle.sh:3777-3781 and wait_lead's (3875-3879) name the list instead of repeating it. (2) lead_queue (2807-2836) calls stuck_lines just before pr_lines, and main_red_lines, reported_lines and sign_blocked_lines after it. Define each beside lead_queue as a function that prints nothing, with a one-line comment naming the story that fills it (stuck-builder-line, main-red-line, reported-line, sign-blocked-line). (3) The docs that list every line become pointers that stay true as lines are added: docs/reference.md's `swarm.sh wait --lead` command row (3456) ends 'or any other line § The lead lists'; § The lead's first-read sentence (383) and commands/swarm.md's (360) name the five quiet lines instead of the alerts; AGENTS.md's wait --lead bullet (76) points at § The lead for every line; bin/swarm.sh's usage line for wait --lead (9) ends the same way. No poll prints a line it does not print today. docs/method.md's list of wait --lead line kinds (:83) names the four new lines too.

**Done when:**
- tests/wait_lead_test.sh quiet first read cases: with no .swarm/lead/seen, a held: line and an idle: line print nothing on the run's first read, and a no-agent: line prints.
- Removing held: from LEAD_QUIET turns the held case red (copy-aside proof).
- tests/unmerged_conflict_test.sh's first-read unmerged: case (:215) and the rest of tests/wait_lead_test.sh pass unchanged.
- docs/reference.md's wait --lead row, its first-read sentence in § The lead, commands/swarm.md's first-read sentence, AGENTS.md's wait --lead bullet and the usage line point at § The lead; tests/doc_check_test.sh passes.
- shellcheck, tests/loose_match_test.sh and tests/timeouts_test.sh pass.

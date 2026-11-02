---
kind: code
status: ready
epic: board-loose-ends
depends_on: []
touches: [bin/lib/lifecycle.sh:wait_lead (timeout line, interruptible sleep, header comment), bin/lib/lifecycle.sh:lead_lock (EXIT and TERM traps), tests/wait_lead_test.sh:timeout cases (:4, :257, :298, :306, :410, :707, and one new), tests/unsent_brief_test.sh:timeout asserts (if any pin a silent exit), tests/no_agent_test.sh:timeout asserts (if any pin a silent exit), tests/escalate_triggers_test.sh:timeout asserts (if any pin a silent exit), commands/swarm.md:timeout sentence (wait --lead step, :426-428), docs/reference-lead.md:polling paragraph (§ The lead, :97-130)]
estimate_lines: 160
easy: false
---

# wait --lead: every exit prints a line (timeout, replaced run, error)

In the v0.30.0 build the lead logged 'wait --lead exited 1 with no output' 14 times, about an hour apart (events.tsv incidents 2026-10-30T13:28:02Z to 2026-10-31T14:42:58Z). That is the one-hour timeout, which returns 1 with nothing printed by design (bin/lib/lifecycle.sh:4577, 4593; commands/swarm.md:426-428). A kill would exit 143, not 1. Make every exit print one stdout line. (1) At the timeout, wait_lead prints `timeout: nothing new in <N> min, exit: swarm.sh wait --lead`, N being the timeout in whole minutes rounded up, and still exits 1. (2) A run that lead_lock stops for a newer one (lifecycle.sh:4556-4570) prints `replaced: a newer wait --lead watches now` and ends inside lead_lock's 5 s wait. That needs a TERM trap, and the poll's sleep made interruptible (`sleep & wait`, the sleep child killed in the trap); bash 3.2. (3) Any other non-zero exit with nothing printed on stdout (a die, or a set -e stop inside a poll) prints `wait-failed: exit <rc>, exit: swarm.sh wait --lead`. That comes from the one EXIT trap lead_lock sets, which keeps its pid-file removal. None of the three is a queue item: not saved to LEAD_SEEN, no lead-woken event. Exit codes stay as they are (0 a line, 1 the timeout), so callers that read them are unchanged. Flip every test that pins the silent exit: tests/wait_lead_test.sh's header (:4) and cases :257, :298, :306, :410 and :707. Also flip any check in another suite that expects empty wait --lead output at a timeout (grep tests/; unsent_brief_test.sh, no_agent_test.sh and escalate_triggers_test.sh hold candidates). Docs: commands/swarm.md:426-428, the polling paragraph of docs/reference-lead.md § The lead (:97-130) and wait_lead's header comment say what each line means. A run with timeout 0 (`wait --lead 0`, a single read) prints no `timeout:` line: about 13 suites read the queue that way and expect silence (tests/unmerged_conflict_test.sh:140, restart_test.sh:128-130, idle_queue_test.sh:63-64 and others), and other v0.31.0 stories add such checks. So no other wait --lead story depends on this one. `wait-failed:` keeps the run's own non-zero exit code, and it also covers a failure before the first poll (invalid arguments, a lock that cannot be taken): set the EXIT trap before argument checks, or print the line on those paths directly. lead_queue's failures are swallowed today (lifecycle.sh:4488, 4588): pass its status up so a failed producer reaches the trap instead of ending as a timeout.

**Done when:**
- tests/wait_lead_test.sh: a run with a short timeout and no change prints exactly one `timeout:` line and exits 1. The cases at :298, :306, :410 and :707 assert that line, not empty output.
- A `wait --lead 0` run with no change prints nothing and exits 1, as today (a check in tests/wait_lead_test.sh).
- The :257 case: a run stopped by a newer one prints one `replaced:` line and ends within 5 s, and the newer run keeps watching.
- A new case: a poll whose lead_queue fails (a stub that exits non-zero) prints one `wait-failed: exit <rc>` line on stdout. With the EXIT trap's print removed (copy-aside proof), that case goes red.
- Command-entry cases: invalid arguments, a lock that cannot be taken, and a failing queue producer each print exactly one `wait-failed:` line, exit with that failure's own non-zero code, and never end as a timeout.
- A case shows that no `timeout:`, `replaced:` or `wait-failed:` line is in .swarm/lead/seen or logged as lead-woken.
- commands/swarm.md and docs/reference-lead.md say what each of the three lines means. tests/doc_check_test.sh, shellcheck and scripts/select-tests.sh --run pass.

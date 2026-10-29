---
kind: code
status: blocked
epic: lead-woken
depends_on: [main-red-read, fix-main-outside-merge]
needs: [main-red-read (the per-head state file and the red verdict), fix-main-outside-merge (fix_main for a red found outside a merge)]
touches: [bin/swarm.sh:_fix-main entry (new), bin/lib/lifecycle.sh:main_red_lines fix start, tests/wait_lead_test.sh:main-red fix cases, commands/swarm.md:the main-red paragraph]
estimate_lines: 150
easy: false
risk: high
---

# A red base head found by wait --lead gets its fix-main story through a detached, guarded fix_main

Split from main-red-line (skeptic review, 2026-10-29). fix_main is a shell function (merge.sh:1499) with no command, so this adds a private `swarm.sh _fix-main <repo> <base> <sha>` entry, run detached, pinned to the project, its output to a file, so wait --lead returning or lead_lock stopping a run does not kill it. It never starts while a `swarm.sh merge` of this project into that repo and base is live (the unmerged: line's ps read, lifecycle.sh:2677), and fix_main rechecks key_reds under fix_lock before it writes. A head counts as handled only once its fix-main story and main-red event exist; a run that fails or is killed before then is retried on a later poll, at most twice, then the line names the lead's check. Its log read uses a small SWARM_FIX_MAIN_LOG_SECONDS, never 600 s inside lead_queue. `_fix-main` rereads the red head's failed checks (ci_gate on that sha, bounded) and passes them to fix_main as its fourth argument, so the story records the check names and failed-run URLs as a merge's fix-main does.

**Done when:**
- A red head with no live merge gets one fix-main story and one main-red event from the detached run; a second poll starts no second run.
- With a live swarm.sh merge into the same base (a fixture ps line), no run starts.
- A run killed before it writes is retried on the next poll, and after two failures the line names the lead's check instead.
- The fix-main story written by the detached run names the failed check and its run URL from the fixture's red checks.

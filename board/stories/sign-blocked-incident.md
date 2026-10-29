---
kind: code
status: blocked
epic: delivery-liveness
depends_on: [stall-reads-bg, sign-blocked-probe]
needs: [stall-reads-bg: agent_stalled's bg_running check (same part), which this check follows, sign-blocked-probe: sign_blocked <worktree>]
touches: [bin/lib/agents.sh:agent_stalled, bin/lib/agents.sh:login_incident skip list, tests/agent_liveness_test.sh:sign-blocked stall cases, tests/incidents_test.sh:sign-blocked skip case, docs/reference.md:the stall paragraph in Building, docs/reference.md:Logs and outcomes incident kinds, docs/lead-by-hand.md:#687 entry, docs/lead-by-hand.md:#689 entry]
estimate_lines: 140
easy: false
---

# A builder that cannot sign is not stalled, and is logged once

Needs from stall-reads-bg: agent_stalled's not-stalled checks next to test_running, where this check goes after them. Needs from sign-blocked-probe: `sign_blocked <worktree>`. agent_stalled finds the builder's worktree as story_work_time does (repo_dir, worktree_for). After test_running and bg_running, it returns not-stalled when sign_blocked is true, and writes `record_event incident <name> "sign-blocked: <slug> (unsigned work since <time>)"`, where <time> is the worktree's last commit in ISO UTC. It writes once per transition: the write is skipped when events.tsv already holds that exact outcome for <name> (grep -F). Both callers run agent_stalled inside $(...), so no variable survives from one poll to the next. A new commit gives a new <time>, so a later block is logged again. sign-blocked joins login_incident's skip list (agents.sh:1638), so it resets no login check. Docs: the wait --stall paragraph, and the incident kinds in Logs and outcomes (reference.md:1855). docs/lead-by-hand.md's #687 entry (30-36) and #689 entry (45-49) are removed. The wait --lead line for it belongs to lead-woken. The incident is logged once per change of state, blocked then clear then blocked logs twice, keyed on the probe's state change, not on the incident text or the last commit's time. The probe's clear state is logged too (a sign-clear event once per change of state), and the dedupe compares against the newest of sign-blocked and sign-clear for that builder, not a grep over all of events.tsv.

**Done when:**
- tests/agent_liveness_test.sh: a builder past stall_minutes with uncommitted work and a stubbed blocked probe gets no `stalled:` across three `wait --stall` polls, and events.tsv holds exactly one `sign-blocked: <slug> (unsigned work since <time>)` incident for it.
- After a new commit in the worktree and a blocked probe again, a second incident with the new time is written.
- False case: idle, no commits, no background task, no test run and a clear probe give `stalled:` and exit 3, with no sign-blocked incident.
- tests/incidents_test.sh: an expired login after a sign-blocked incident still logs one login incident; removing sign-blocked from the skip regex turns it red (copy-aside proof).
- docs/reference.md names the probe in the wait --stall paragraph and lists sign-blocked among the incident kinds; docs/lead-by-hand.md has no #687 or #689 entry.
- A blocked, clear, blocked sequence with no new commit logs two sign-blocked incidents.
- events.tsv carries sign-blocked, sign-clear, sign-blocked for that sequence.

---
kind: code
status: blocked
epic: lead-woken
depends_on: [lead-alerts-wired]
needs: [lead-alerts-wired: stuck_lines, empty and called in lead_queue before pr_lines (same part), and stuck: being an alert on a first read]
touches: [bin/lib/lifecycle.sh:stuck_lines, bin/lib/lifecycle.sh:pr_lines conflict line, tests/wait_lead_test.sh:stuck cases, tests/unmerged_conflict_test.sh:stuck replaces conflict case, docs/reference.md:the stuck row, commands/swarm.md:the stuck paragraph]
estimate_lines: 280
easy: false
---

# wait --lead names a builder stuck on findings or a conflict (stuck:)

Needs from lead-alerts-wired: stuck_lines, empty and called in lead_queue just before pr_lines, and the quiet list that makes stuck: an alert. Fill stuck_lines. It prints `stuck: <slug> <PR URL> (<findings|conflict> pending <N> min), exit: swarm.sh tell <slug> resume <file>` for an open story PR when all of these hold: (a) its head sha, read from LEAD_PRS (the heads pass's rows, lifecycle.sh:2612-2650; LEAD_HEADS holds verdicts, no sha), has not changed for N minutes; (b) since that head was first seen, a findings tell reached the builder (events.tsv tell or tell:findings with ok, as findings_told reads it, agents.sh:2460) or the PR is CONFLICTING; (c) the builder is live in the poll's herdr list (LEAD_AGENTS) and read_state says idle. N is a constant, STUCK_MINUTES=60 (SWARM_STUCK_MINUTES for tests), like STOP_GRACE (lifecycle.sh:2728-2731), not a board setting. The line prints N, the threshold, never the elapsed minutes: LEAD_SEEN dedupes whole lines (lifecycle.sh:3813-3816), so a changing number would wake the lead every poll. Keep '<slug> <head sha> <first-seen epoch>' per open PR in a new file under .swarm/lead, rewritten each poll so a merged or closed PR drops out. Do not use .swarm/lead/stuck: that is LEAD_STUCK, prompt_lines' file (lifecycle.sh:2878). Run the checks cheapest first: file reads, then read_state, then bg_running (agents.sh:1215), then a test-run check. A live background task or a selected test run under way prints nothing. test_running's herdr call (agents.sh:1225-1231) has no bound, and within cannot wrap a shell function. So call `herdr pane process-info` under within from lifecycle.sh, and pass its output to panes.py's test_running as agents.sh does. Do not edit agents.sh: delivery-liveness owns it in v0.30.0. One line per PR: when stuck_lines prints for a PR, pr_lines (2682-2700) prints no conflict: for it, through a variable stuck_lines sets in the same lead_queue subshell. As pr_lines does, a PR whose repo read failed, or whose mergeable is UNKNOWN, keeps the stuck: line LEAD_SEEN has. Docs: a stuck bullet in docs/reference.md § The lead, after conflict:, saying N. Add a commands/swarm.md paragraph that tells this line from `wait`'s `stuck: api error` and `stuck: no output` (commands/swarm.md:221, 388): this one names a builder with a PR and a pending item. N is 60 minutes by default, overridable with SWARM_STUCK_MINUTES (Open question 4); the release-v0-30-0 lead story asks the user to confirm it before the cut, and a change is one constant.

**Done when:**
- tests/wait_lead_test.sh stuck cases: a fixture PR whose head is unchanged past SWARM_STUCK_MINUTES, with a findings tell logged ok since and an idle live builder, prints `stuck: <slug> <URL> (findings pending <N> min), exit: swarm.sh tell <slug> resume <file>`, with N the threshold.
- tests/unmerged_conflict_test.sh: a CONFLICTING PR in the same state prints `(conflict pending <N> min)` and no conflict: line for that PR; a conflicting PR not yet past N still prints its conflict: line.
- False cases, each printing no stuck: line: the head changed within N; no findings tell and not conflicting; the builder busy; a stub herdr process-info showing a selected test run; a builder whose fixture transcript has a live background task.
- Two polls in a row print the same stuck: line text.
- Removing the test-run check turns its false case red (copy-aside proof).
- shellcheck, tests/loose_match_test.sh and tests/timeouts_test.sh pass; docs/reference.md § The lead and commands/swarm.md name the line and N.

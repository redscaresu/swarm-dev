---
kind: code
status: blocked
epic: lead-woken
depends_on: [lead-alerts-wired, sign-blocked-incident]
needs: [lead-alerts-wired: sign_blocked_lines, empty and called in lead_queue after pr_lines (same part), and sign-blocked: being an alert, sign-blocked-incident: the sign-blocked incident and sign-clear events it writes once per change of state]
touches: [bin/lib/lifecycle.sh:sign_blocked_lines, tests/wait_lead_test.sh:sign-blocked cases, docs/reference.md:the sign-blocked row, commands/swarm.md:the sign-blocked paragraph]
estimate_lines: 160
easy: false
---

# wait --lead names the builders that cannot sign their work (sign-blocked:)

Needs from lead-alerts-wired: the empty sign_blocked_lines that lead_queue calls after pr_lines, and sign-blocked: being an alert. Needs from sign-blocked-incident: its `incident <name> 'sign-blocked: <slug> (unsigned work since <time>)'` and sign-clear events, one per change of state. Read their exact shape from that merged PR. Fill sign_blocked_lines. For each builder, take the newer of its last sign-blocked incident and its last sign-clear in events.tsv. A builder counts when that newer event is sign-blocked, it is still live in the poll's herdr list (LEAD_AGENTS), and its worktree still has uncommitted work (git status --porcelain, bounded). All such builders go on one line, slugs sorted so the text stays the same for LEAD_SEEN: `sign-blocked: <slug>, <slug> (their signing key is locked; unsigned work in their worktrees), exit: unlock your signing key in your shell (gpg-agent or ssh-agent), then swarm.sh tell <slug> resume <file> for each`. The text names no gpg-agent cache alone, because the probe also covers ssh signing. The poll makes no probe call and no gpg, gpg-connect-agent, ssh-add or ssh-keygen call: the conductors' wait --stall writes the events. Docs: a sign-blocked bullet in docs/reference.md § The lead (the line comes once a builder's stall check has run, so up to stall_minutes late), and a commands/swarm.md paragraph.

**Done when:**
- tests/wait_lead_test.sh sign-blocked cases: two live builders whose newest event is a sign-blocked incident and whose worktrees hold an uncommitted edit print one line naming both, slugs sorted.
- False cases print nothing: the builder's newest event is sign-clear; its worktree is clean; it is not in the herdr list; there is no sign-blocked event.
- A blocked, clear, blocked sequence prints the line, then nothing, then the line again.
- Stub gpg, gpg-connect-agent, ssh-add and ssh-keygen on PATH log no call during the polls.
- Removing the worktree check turns the clean-worktree case red (copy-aside proof).
- shellcheck, tests/loose_match_test.sh and tests/timeouts_test.sh pass.

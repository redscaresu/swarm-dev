---
kind: code
status: blocked
depends_on: [upgrade-skip-closed]
needs: [upgrade-skip-closed (its closed markers and upgrade_open's skip; this story ties the markers to a pane)]
touches: [bin/lib/lifecycle.sh:upgrade_open, bin/lib/lifecycle.sh:upgrade_reread, tests/upgrade_test.sh:same-name restart case]
estimate_lines: 90
easy: true
---

# upgrade moves a builder restarted under a closed agent's name

A codex pass on #829 (upgrade-skip-closed) found this, deferred from that PR. Needs from upgrade-skip-closed: its closed markers and upgrade_open's skip.

The pre-round check marks closed agents by name, before conductors are paused. If a busy conductor restarts a closed builder under the same name before it writes its handover, upgrade_reread sees the new one, but upgrade_open still leaves it out. Upgrade can then report success while the new builder stays on the old version.

Tie each closed marker to the pane or session it saw, and drop the marker when a reread finds a different one under that name.

**Done when:**
- A case: an agent is marked closed, then a new pane under the same name appears before the round. The upgrade moves the new one and does not count it as skipped
- A closed agent with no replacement is still skipped
- The first case goes red with the change removed, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- scripts/select-tests.sh --run passes

---
kind: code
fix: true
status: ready
depends_on: []
touches: [bin/lib/lifecycle.sh:restart_build manual-mode fresh start, bin/lib/lifecycle.sh:manual exit, tests/restart_test.sh:manual-mode cases, docs/reference-lead.md:manual line exit sentence]
estimate_lines: 150
---

# A builder that dropped to manual mode is restarted in a fresh session, not resumed into manual mode again

From the 2026-11-20 run. port-map-floor's Claude session dropped from auto to manual mode. It had been started with `--permission-mode auto`, but its pane footer read `manual mode on`, and every Bash command with a pipe, subshell or `cd` then stopped on a permission prompt. Over about four hours the lead and the user answered more than ten of them by hand.

`wait --lead` already prints a `manual` line for a ready story's builder, and its exit is to close the pane and `swarm.sh restart` it. But restart_build reopens the same Claude session with `--resume`, and the resumed session came back in manual mode, so the restart fixed nothing. What did fix it was `swarm.sh step-up`, which starts a new session on the same branch.

Change restart_build, and the `manual` exit in the lead queue that leads to it: when the builder's last known state is manual mode (the lead queue's manual record for it), restart starts a fresh session in the story's worktree, on its branch, with the build brief plus a short note. The note names the PR if one is open, the branch head, and that the session was restarted out of manual mode. It does not `--resume`. Every other restart resumes as today.

**Done when:**
- tests/restart_test.sh: with a manual record for a ready story's builder, `swarm.sh restart <slug>` starts the agent without `--resume` and with the restart note in its brief; with the change removed it passes `--resume` (shown on a worktree copy, FAIL lines quoted in the PR)
- With no manual record, restart still passes `--resume`, as today
- docs/reference-lead.md's `manual` line says a restart starts a fresh session, and why
- scripts/select-tests.sh --run passes

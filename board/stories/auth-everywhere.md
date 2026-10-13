---
kind: code
status: blocked
blocked_by: [release-agent-state]
depends_on: [release-agent-state]
touches: [bin/swarm.sh (status_report, dash_render, next_step, outcomes), commands/plan-epic.md, commands/plan-hld.md, tests/dash_test.sh, tests/review_test.sh, tests/outcomes_test.sh, docs/dash.md, README.md (When /swarm stops for you)]
---

# An expired login shows everywhere, not only through `wait`, and `outcomes` splits tells by kind

Follow-ups from the agent-state wave-5 conductor (2026-10-13), declined there as outside its stories:

- `auth` is visible only through `wait`: `status`, `dash` and `next` show an agent stopped on an expired
  login as idle. Each reads PANES_PY's `login_expired` for a Claude agent that is idle, and shows it as
  needing the user (`! auth: run /login`), never idle.
- `/plan-epic` and `/plan-hld` have no rule for `auth` from a planner's `wait`: they say what it means
  and stop for the user's `/login`, then resume the planners, as `/swarm` does.
- `swarm.sh outcomes` counts a refused tell and `tell:nudge` as tells. Now that the kind is logged, it
  prints `tells_findings`, `tells_nudge` and `tells_resume` in place of `tells`, and does not count a
  refused tell.

**Done when:**
- A fixture agent that is idle with an expired login shows `auth` in `status`, `dash` (needs-you) and `next`, and is not counted as idle; shown red on the old code.
- plan-epic.md and plan-hld.md each name `auth` and the `/login` step.
- outcomes' columns split tells by kind, a refused tell is not counted, and outcomes_test covers both.
- README's "When `/swarm` stops for you" and docs/dash.md match; the humanizer ran over them and the PR description.
- No plugin.json bump.

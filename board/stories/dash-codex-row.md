---
kind: code
status: blocked
blocked_by: [codex-time-limit, dash-lead-queue]
epic: dash-tells-the-truth
depends_on: [codex-time-limit, dash-lead-queue]
touches: [bin/swarm.sh:codex_review, bin/swarm.sh:dash_render (codex rows), tests/codex_test.sh, tests/dash_test.sh (new block), docs/dash.md (codex row)]
---

# A running codex review shows in the dash with its age

codex-time-limit's codex_review leaves no trace while it runs: main logs a command only after it ends (bin/swarm.sh:3953-3961), and its scope has no pid file (board/stories/codex-time-limit.md:13, :22-27). So this story adds one to codex_review: at start write `${STATE_DIR}/codex-review.<pid>` holding start epoch, base and cwd; remove it on every exit path (normal, die, timeout). Briefs run codex-review with SWARM_PROJECT=<project>, so a worktree's run writes to the main project's .swarm/state. dash_render reads `codex-review.*` in DASH_STATE, keeps the files whose pid is alive (os.kill(pid, 0)), and shows one row per live review: `codex review <cwd basename> vs <base>` with its age, under the epic of the story its worktree belongs to, else under no epic. dash only reads: a dead pid's file is ignored, never removed.

**Done when:**
- tests/codex_test.sh: while the stub sleeps, `.swarm/state/codex-review.<pid>` exists with the base and cwd; after a normal exit, a stub error and a timeout, no such file is left. tests/dash_test.sh: a state file for a live pid (the test's own background sleep) started 7 min ago shows a row containing `codex review` and `7m`; a file for a dead pid shows no row; the snapshot check proves dash left both files in place. The PR shows each check failing with its code removed. The epic's checks before every stage pass.

**From review (binding; overrides the scope above where they differ):**
- codex_review writes the marker as .swarm/state/codex-review.$$ (main's pid, alive for the whole run; bash 3.2 has no BASHPID) and at start deletes any codex-review.* whose pid is dead. dash shows no row for a marker older than codex_minutes plus 1 min.
- The row is informational: it goes in the agents/epic area, never in needs you or the lead's queue. Its epic resolves via epic_for with 'epic-' stripped from the worktree basename.
- The new dash block checks with its own before/after cksum that both marker files survive the dash run (not the :145/:380 snapshot). codex_test checks a pre-existing dead-pid marker is gone after a run; dash_test checks a live-pid marker older than the limit shows no row.

---
kind: code
status: blocked
blocked_by: [session-reader-and-wait]
epic: agent-state-from-the-session
depends_on: [session-reader-and-wait]
touches: [bin/swarm.sh:PANES_PY.agent_state, bin/swarm.sh:status_report, bin/swarm.sh:dash_render, tests/dash_test.sh (fixtures :64-82, :125-143), tests/review_test.sh (status block :255-265), scripts/demo-dash.sh, docs/method.md (§ Building, Watching it), docs/dash.md]
---

# `status` and `dash` read the session and show waitingFor, with `!` for unknown or gone

PANES_PY.agent_state takes the reader's entry as an optional argument, so tidy_panes's call (:2564) does not change. busy maps to working, idle to idle, waiting to WAITING with waitingFor, and unknown and gone to needs-a-look. herdr's word is used only for codex, no-session and retired agents. status_report and dash_render make one list call per run or frame and pass it in env, as DASH_AGENTS is. dash's stall list (:2004-2015) uses the session's busy. The `words` map (:2176) and the sym dict (:2189) gain gone. `reported` still comes from idle plus a report file. With no `claude` on PATH, dash shows recorded sessions as unknown. scripts/demo-dash.sh stubs claude. In this PR, update docs/method.md § Building 'Watching it' and docs/dash.md.

**Done when:** When herdr says `done` and the session says `busy`, both status and dash show the agent as working, and dash lists it as stalled when its signs are old. A `waiting` agent shows its waitingFor in status and in dash's needs-you line (dash_test.sh:131 rewritten). A missing field shows `!` unknown, and a recorded session with no entry shows `!` gone, never idle. A reused name shows the newer line's role. The status block of review_test (:255-265) is rewritten against the stub. tidy's output on its fixture does not change. scripts/demo-dash.sh runs and passes shellcheck. Each new test is shown red on the old code.

**From review (binding; overrides the scope above where they differ):**
- Replace the reused-name check (it passes on the old code): two agents.tsv lines for one name, the older retired, where the older session is busy and the newer idle (and the reverse); status and dash show the newer session's state, shown red on the old code.
- Fallback checks: a codex agent whose herdr status is `blocked` still shows WAITING; a no-session ('-') agent shows herdr's word; a retired `<name>-done` pane shows retired even when the newest line for <name> is a busy session.
- status prints 'unknown: no session state' and 'gone: session ended' (or equally plain words) and counts both as need-a-look, never idle or done.
- Rename review_test's pane named `gone` (tests/review_test.sh:252,262) so the check is not ambiguous. Add LEGEND (:2048) to the scope: gone and unknown under '! needs you'.
- docs/method.md § Building is also edited by off-screen-nudge in this wave: the second to merge rebases.

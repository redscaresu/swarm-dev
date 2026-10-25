---
kind: code
status: blocked
epic: stage-gating
depends_on: [stage-release-gate, next-step-arms-check, stage-release-arm]
needs: [stage-release-gate: the stage reader in bin/lib/board.sh:release_stage, next-step-arms-check: the arm check in tests/next_test.sh, which must see the new stage step, stage-release-arm: its commands/swarm.md and docs/reference.md § Releases text, which this story's stage arm extends]
touches: [bin/lib/board.sh:next_step stage arm, bin/lib/board.sh:stage_due (new helper), bin/lib/board.sh:waiting_on_user, bin/lib/dash_render.py:needs-you rows, commands/swarm.md:stage arm (new), commands/swarm.md:gate arm, tests/next_test.sh:stage cases, tests/dash_needs_you_test.sh:staged draft row, docs/reference.md:Releases stage step, AGENTS.md:swarm.sh next line, README.md:When /swarm-dev:swarm stops for you]
estimate_lines: 230
easy: false
---

# A staged draft epic waits for its stage, and next names the flip once the stage before it is tagged

Needs stage-release-gate's stage reader and version compare (bin/lib/board.sh:release_stage) and next-step-arms-check's arm check (tests/next_test.sh). A staged draft is a draft epic with a valid stage: and an hld:. T is the lowest stage among staged drafts and P the minor before it (v0.30.0 gives v0.29.0; a v<x>.0.0 stage has no P, and its drafts stay as today). When tag v<P> is on origin/<base> (release_due's ancestor check, local refs), next_step prints `stage v<T>` with the why `set <slugs> active (board PR under the epics grant)`, in the main flow before plannable_epic (bin/lib/board.sh:252); the conductor branch (:207-243) is unchanged. waiting_on_user (:979) lists a staged draft as `  staged epic: <slug>, stage v<T>, after v<P>`, never `run /epic`; status prints it as is. dash_render.py drops the `agree draft epic` row (:419-420) for a staged draft and shows `stage <v>, after <prev>` in the lead's queue. Add a `stage v<S>` arm to commands/swarm.md after `story <slug>`: open a board PR with swarm.sh board-pr that sets those epics active, land it with swarm.sh merge --board under the HLD's epics grant, and stop and tell the user if merge refuses. In the gate arm (:331-342), a staged epic needs nothing from the user. hooks/lead-stop.sh stays unchanged (an unknown step allows the stop, :9-11): say so in docs/reference.md § Releases. Update AGENTS.md's `swarm.sh next` line (:71) and add a row to README.md's When /swarm-dev:swarm stops for you. no-agent-alert's next_step story merges after this one and names it in depends_on.

Review fix (critic): no-agent-alert also edits bin/lib/dash_render.py's lead queue rows; if its story that does is open when this builds, merge after it.

**Done when:**
- tests/next_test.sh: with tag v1.2.0 on origin/main, draft epics a and b carrying `stage: v1.3.0` and `hld:`, and an active epic with no stories, next's first line is `stage v1.3.0` and its why names `set a b active (board PR under the epics grant)`.
- With only a draft c carrying `stage: v1.4.0` and `hld:`, next prints no stage step, and its gate lists `staged epic: c, stage v1.4.0, after v1.3.0` and no `run /epic c`; a draft with stage: but no hld:, and one with no stage:, still read `draft epic: <slug>, run /epic <slug>`.
- tests/dash_needs_you_test.sh: a staged draft shows `stage v1.4.0, after v1.3.0` and no `agree draft epic` row; the unstaged draft d keeps `agree draft epic d: /epic d`.
- next-step-arms-check's check records `stage` and passes, and fails if the new swarm.md stage arm is removed.
- docs/reference.md names the stage step and that hooks/lead-stop.sh allows the stop on it; `git diff origin/main -- hooks/lead-stop.sh` is empty; doc_check passes.

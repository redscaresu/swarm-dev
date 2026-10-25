---
kind: code
status: blocked
epic: no-agent-alert
depends_on: [no-agent-rule]
needs: [no-agent-rule: no_agent_exit in bin/lib/lifecycle.sh, whose ready-story exit this story extends]
touches: [bin/lib/lifecycle.sh:no_agent_exit, bin/lib/lifecycle.sh:restart_build (new), bin/swarm.sh:dispatch restart, bin/swarm.sh:usage header, docs/reference.md:commands table, tests/restart_test.sh:restart cases (new file), tests/no_agent_test.sh:restart exit case]
estimate_lines: 260
easy: false
---

# swarm.sh restart starts a gone builder again, and the no-agent line names it

Uses no-agent-rule's no_agent_exit (bin/lib/lifecycle.sh). Add `swarm.sh restart <slug>`. It works on a started story (ready, with a worktree) whose builder herdr does not list, in an epic or as a one-off. It starts the builder again in the same worktree and branch, in the story's tab, as build_story's start_agent call places it (build.sh:541). If resume_file recorded a resume command for the builder's last Claude session (agents.sh:394-415, RESUME_DIR/<session>.argv), it reopens that session. Otherwise it starts a fresh builder on the last model (builder_model, lifecycle.sh:799) with handover_brief (lifecycle.sh:705), as start_rung does but without changing the model.

It refuses and starts nothing when the builder is listed, there is no worktree, the story is not ready, it is kind: lead, held or escalated, or it has a .step-up marker (use step-up --resume instead). It logs `restart <slug> ok (...)`. build_started and review_round do not read that line, because a restart continues the same build.

The command is named restart because `resume` is already wait's events line kind (swarm.sh:566), a tell kind and a next step. no_agent_exit puts `swarm.sh restart <slug>, or ` before the hold exit. List the command in swarm.sh's header and in reference.md § Commands.

**Done when:**
- Tests for an epic story and a one-off whose builder pane is gone: restart starts one builder in the story's worktree, on its branch, in its tab (herdr stub). With a recorded session it resumes that session; without one it starts a fresh builder on the last model with a handover brief.
- Refusal tests (builder listed, no worktree, a .step-up marker, kind: lead): nothing starts, and the message says why.
- A no-agent test: the line's exit names `swarm.sh restart <slug>`. After running it (stubbed), the next poll is silent.
- A test: build_started and review_round give the same answer before and after a restart line.
- reference.md and swarm.sh's header list the command, and command_names_test passes. The humanizer ran over the changed reference.md prose, and the PR says so.

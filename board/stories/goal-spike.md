---
kind: lead
status: ready
epic: goal-for-builders
depends_on: []
touches: []
---

# Spike: which goal form takes in a builder's herdr pane with hooks on, when it sets, and what each goal end writes to the transcript

Tests Claude Code itself, so it may run before fable-on-call is built; it edits no code. It is a lead story for two reasons: it ends in the user's choice of form (the epic's Your part), and its scratch folder needs the user's trust answer, which an agent must never give (AGENTS.md). From this repo's main checkout in herdr, the lead starts throwaway sessions with builders' flags through `swarm.sh agent goal-spike goal-spike <scratch dir> code <brief>` (start_agent: --permission-mode auto, --session-id, no --bare, hooks on), with a one-line brief that writes a file and prints it. It tries three forms. (1) `/goal <multi-line condition ending 'or stop after 3 more turns'>` pasted with `herdr agent prompt` as deliver_prompt does, once while the brief's turn runs and once after it went idle, noting whether it sets in each state and what herdr reports after the paste. (2) The launch-prompt form, `/goal ...` as claude's launch argument after `herdr agent start ... --`. (3) A prompt Stop hook with the same condition, passed per session with --settings (as builder_subagent_model is) and as the worktree's .claude/settings.local.json. For the form that sets, it records the .jsonl entry each of these writes: set, refused (a session with --settings '{"disableAllHooks":true}'), met, impossible (a condition the session cannot show) and bound. It checks one goal session's .jsonl for the judge's tokens and whether `swarm.sh cost` counts them. **You:** trust the scratch folder when Claude Code asks. **You:** read the report and say which form the epic builds and the default bound, or stop the epic. If you stop it, the lead marks the epic done with a note in the HLD's ## Epics and deletes the other goal-for-builders stories.

**Done when:**
- The report on this story says, for each of the three forms, whether it set a goal in a session started with builders' flags, and quotes the .jsonl entry that shows it.
- It says whether /goal sets while the brief's turn runs or only once the session is idle.
- It quotes the .jsonl entry, or says none was written, for a refused, a met, an impossible and a bound goal; goal-delivery and goal-conductor-rule read these.
- It says whether the judge's tokens are in the goal session's .jsonl and whether `swarm.sh cost` counts them, naming the session id.
- It names the default bound, the `claude --version` used, and the lowest version goal needs if above 2.1.145.
- The user's choice (form and bound, or stop) is on the story. With stop, the epic is marked done with a note and no other goal-for-builders story file remains.
- If the chosen form is the Stop hook or the launch-prompt form, or /goal sets only once the session is idle, or a set writes no .jsonl entry, the lead re-scopes goal-delivery, goal-on-findings and goal-wait-no-nudge for it before this file is deleted.

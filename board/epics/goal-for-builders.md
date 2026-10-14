---
status: active
hld: 2026-10-13-builders-use-claude-codes-goal-advisor-and-agent-view
depends_on: [agent-state-from-the-session, fable-on-call]
---

# With `goal` on, each builder works to its story's Done when, and a builder that stops short is accounted for by cause (HLD Goal 3, Rollout 3)

**Done when:**
- The spike, in a herdr pane with hooks on as builders run (`--permission-mode auto`, no `disableAllHooks`, no `--bare`), tries `/goal` after the brief, the launch-prompt form and the settings-level Stop hook; it checks one goal session's .jsonl for the judge's tokens; its report names the form, the default bound and whether `swarm.sh cost` sees the judge. If no form works the epic stops there and is marked done with a note.
- `swarm.sh config` shows `goal` off by default, pinned by the defaults test; the config-table test covers the key.
- With `/goal`: `goal = N` puts the condition (Done when, the reply the brief asks for, `or stop after N more turns`) into the session after the brief is taken up through a deliver_prompt variant; a condition over GOAL_MAX_CHARS (4000) is refused at `story` time naming the story; a `story` whose goal command refuses fails. With the Stop hook: the worktree's settings file is git-ignored or excluded, and a check of the effective `disableAllHooks`/`allowManagedHooksOnly` fails the story.
- `close` takes a cause (met, impossible, stalled, bound, paused, cleared-on-error); with `goal` on it refuses a missing cause. The events log carries the cause name, never text. `impossible` makes the story a `lead` item without counting an attempt.
- With `goal` on, `wait` records no `nudge` (a stub test); a `tell` with findings sets a fresh goal with the same bound; `resume` is counted apart from `nudge`. A cleared-on-error builder stops the wave and is listed for the user.
- commands/plan-epic.md and docs/method.md § Scoping an epic gain one line: a story's **Done when** names what the builder's session can show. README's inner-loop row and § Building describe the goal.
- On one infrafactory epic with `goal` on, the log shows zero `nudge` and every builder that stopped short has a cause, set beside the goal-off baseline from the earlier epics.

**Out of scope:** a goal for conductors. The advisor. Changing `swarm.sh cost`. The decision to leave `goal` on for infrafactory.

**Constraints:** ships off (docs/method.md:171); turning it on is a `lead` story. The spike gates every other story. The condition is built in build_story from the story's **Done when** and story_brief's reply sentences. The cause is read by the conductor from the transcript and reply, never a screen. New key: CFG_ default `off`, CONFIG_KEYS, validator (off or positive integer), method table row. CLAUDE_CODE_GOAL_CHECKIN_MINUTES stays at its default. Needs Claude Code 2.1.269 or later; `require_claude` holds the pin, raised here if the spike needs it. Starts only after both earlier epics merge (they change deliver_prompt, wait_agent, tell_agent, build_story, close_agent and the conduct modes). bash 3.2. Bump plugin.json.

**Your part:** read the spike's report and say which form the epic builds, or stop it. A `lead` story sets `goal = <bound>` in infrafactory's .claude/swarm/config for one epic; the lead prepares `swarm.sh cost` (with the judge's tokens, or says they are missing) and the nudge counts against the baseline, and you decide whether it stays on. Agents never edit infrafactory's config.

**Spike result (2026-10-14, Claude Code 2.1.299):** `/goal` pasted into the pane (form 1) sets mid-turn or idle and is the only form that writes `goal_status` (set: `sentinel:true`; end: `met:true` with `reason`, `iterations`, `tokens`). The launch-prompt form works but must precede the brief; a `--settings` Stop hook blocks stopping but records nothing. Claude Code has no default turn bound, writes the bound and an impossible escape as `met:true` (only `reason` tells them apart), refuses `/goal` when hooks are restricted, and keeps the judge's tokens only in `goal_status.tokens`, which `swarm.sh cost` does not read. **User's choice: form 1, default bound 5.** The affected stories carry a binding "From the spike" note.

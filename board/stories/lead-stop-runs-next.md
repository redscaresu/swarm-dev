---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [hooks/lead-stop.sh, hooks/hooks.json, tests/lead_stop_test.sh, docs/method.md]
estimate_lines: 120
easy: false
---

# The lead cannot end a turn while `next` names a step it should be running

On 2026-10-21 `next` printed `plan-epic goal-for-builders` for hours. The lead answered three status questions and each time told the user it would start the plan "next", then ended its turn. A Claude Code session only acts when a message or a background notification wakes it, so the promised step waited until the user asked why. This is the second time: an idle board on 2026-10-18 waited the same way. A memory rule did not stop it the second time, so the hook makes the check mechanical.

Add a Stop hook, `hooks/lead-stop.sh`, registered in hooks/hooks.json beside agent-state.sh. It runs only in the lead's session: a swarm project (`.claude/swarm/` exists in the session's cwd or `SWARM_PROJECT`), and not a swarm agent (`SWARM_AGENT` unset). It runs `swarm.sh next` with a 10-second timeout and reads its first line:
- `plan-epic`, `story`, `resume`, `collect` or `conduct`: a step the lead acts on. If no `swarm.sh wait` or `plan-epic` agent for that step is running (it checks `swarm.sh status` for an agent named after the step's subject), the hook blocks the stop (`{"decision":"block","reason":"next says: <line>. Start it now, or tell the user why it cannot start."}`).
- `wait`, `gate`, `done`, or anything unknown: allow the stop.
- If `stop_hook_active` is true in the hook's input, it allows the stop, so the hook blocks at most once per turn. A lead that has a reason not to act says it in that turn and stops.
- Any error (no swarm.sh, a timeout, next exits non-zero) allows the stop and writes nothing to stdout.

It logs `lead-stop <step> blocked|allowed` to the events log so `flow` can count how often the lead was caught. It ships on, with no config key: it only asks the lead to do what `next` already says, and a block costs one extra turn.

docs/method.md § The lead gains one line: the lead's turn does not end while `next` names a step it runs.

**Done when:**
- tests/lead_stop_test.sh drives the hook with a stub swarm.sh and pins each case: a `plan-epic X` line with no agent running blocks with that line in the reason; the same line with an agent `survey` in scope-X running allows the stop; `wait`, `gate` and `done` allow it; `stop_hook_active: true` allows it; `SWARM_AGENT` set allows it without running next; a stub that sleeps past the timeout or exits 1 allows it with empty stdout.
- Each case's events-log line is checked.
- `make test` passes, and shellcheck passes on the hook.

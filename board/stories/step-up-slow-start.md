---
kind: code
status: ready
depends_on: []
touches: [bin/lib/agents.sh:PROMPT_TIMEOUT_MS and SETTLE_READS, bin/lib/lifecycle.sh:step_up's not-taken-up branch, tests/step_up_slow_start_test.sh (new)]
estimate_lines: 70
easy: false
---

# A step-up to a slow-starting model is not read as a failure

On 2026-10-24 the ladder stepped epic-guard-merge (#450) up from opus to fable. The fable builder's brief read as "not taken up" within the 60 s settle window (`PROMPT_TIMEOUT_MS`, bin/lib/agents.sh:679). So step_up closed the new pane (bin/lib/lifecycle.sh, around :709) after it had already closed the opus builder, and the story sat with no builder until the conductor reported it. `step-up --resume` failed the same way. With `SWARM_PROMPT_TIMEOUT_MS=300000` it started at once: fable at xhigh only needs longer than 60 s to show it is working.

- The settle window depends on the model being started: 300 s for fable, 60 s for the rest. Keep `SWARM_PROMPT_TIMEOUT_MS` as an override.
- When a step-up's new builder reads "not taken up" or "unsure", step_up keeps its pane. It logs a warning and reads it once more over the long window before it closes anything. It closes the pane only if that read still finds it idle with no turn.

**Done when:**
- tests/step_up_slow_start_test.sh (new): with a stubbed herdr where a fable start shows `working` only after 90 s, a step-up to fable succeeds and logs `escalate ... ok`. A model that never shows a turn is still closed and leaves the `--resume` marker.
- `make test` passes.

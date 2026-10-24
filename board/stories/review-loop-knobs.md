---
kind: code
status: blocked
depends_on: [ladder-top-rung-to-lead]
needs: "ladder-top-rung-to-lead: its top-rung round limit (bin/lib/agents.sh tell_agent)"
touches: [bin/swarm.sh:CFG defaults and CONFIG_KEYS, bin/lib/agents.sh:STEP_UP_FINDINGS use in tell_agent, bin/lib/lifecycle.sh:STEP_UP_FINDINGS and STEP_UP_TRIGGERS, tests/config_test.sh, docs/reference.md:Settings]
estimate_lines: 50
easy: true
---

# The review-loop thresholds are settings, not code

The rules that end a review loop are constants: a step-up on the 3rd findings round (`STEP_UP_FINDINGS=3`, bin/lib/lifecycle.sh:549) and, after ladder-top-rung-to-lead, a hold for the lead on the 2nd findings round on the top rung. Tuning them from review-loop-metrics should be a one-line config change, not a code PR.

- Add the config keys `step_up_findings` (default 3) and `top_rung_rounds` (default 2), read wherever those constants are used now. `STEP_UP_TRIGGERS` (bin/lib/lifecycle.sh), the allowlist `step-up` checks, follows the setting, so `step_up_findings = 2` accepts `findings-2`. A value that is not a whole number of 1 or more is refused, with the key named.
- Add a row for each to docs/reference.md § Settings and to the config tests.

**Done when:**
- tests/config_test.sh: the defaults print 3 and 2. With `step_up_findings = 2`, the 2nd findings tell steps up (an escalate-ladder test case). `step_up_findings = 0` is refused.
- `make test` passes.

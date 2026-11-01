---
kind: code
status: ready
epic: stalls-and-effort
depends_on: []
touches: [bin/swarm.sh:settings defaults (CFG_risky_effort), bin/swarm.sh:CONFIG_KEYS, bin/swarm.sh:load_config (risky_effort arm), bin/swarm.sh:policy (code-risky line), docs/method.md:risky_effort row, docs/reference-models.md:risky_effort (Settings bullet), docs/reference-models.md:Model and effort (Building code bullet), tests/config_test.sh:risky_effort cases]
estimate_lines: 60
easy: false
---

# risky_effort: a setting for the effort risk: high code builds run at, default xhigh

No depends_on. A new config key `risky_effort`: `xhigh` (the default, today's effort, so it ships off) or `high`; load_config refuses any other value with a line naming the key and the value. policy's code-risky line (bin/swarm.sh:434) prints `claude opus <risky_effort>`; every other role is unchanged (code stays opus high, escalate fable xhigh), and story_role, step_role and the ladder are untouched. Add CFG_risky_effort=xhigh with a one-line comment in the settings block (bin/swarm.sh:231-253), the key to CONFIG_KEYS (:255) and its arm to load_config (:290-330). Docs: a risky_effort row in method.md § Configuring a project; a risky_effort bullet in reference-models.md § Settings that says it exists for a trial of high against xhigh, and that a swarm.sh older than the release carrying it refuses the line (`unknown key`, load_config's `*)` arm), so the line goes in only after that release is installed; the 'Building code is Opus at high, and at xhigh for risk: high' bullet in § Model and effort names the key. No docs/features.tsv row: the trial's figures come from flow model_fit. Humanizer over the changed docs. Proof: with policy's code-risky line put back to a literal xhigh in a copy, the `high` case goes red.

**Done when:**
- tests/config_test.sh: with no risky_effort line, `swarm.sh policy code-risky` prints `claude opus xhigh` and `swarm.sh config risky_effort` prints `xhigh`.
- tests/config_test.sh: with `risky_effort = high` in the config, `swarm.sh policy code-risky` prints `claude opus high`, while `policy code` prints `claude opus high` and `policy escalate` prints `claude fable xhigh`.
- tests/config_test.sh: `risky_effort = medium` is refused with a message naming risky_effort and medium.
- config_test.sh's check that method.md's table, CONFIG_KEYS and load_config's arms list the same keys passes with risky_effort in all three.
- With policy's code-risky line put back to a literal xhigh in a copy, the `high` case fails; the PR says so.
- scripts/select-tests.sh --run and shellcheck bin/swarm.sh pass.
- `risky_effort = xhigh` is accepted, and other values (low, max, empty) are refused; a check each.

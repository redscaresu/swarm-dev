---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/swarm.sh:CONFIG_KEYS block (CFG defaults, CONFIG_KEYS, load_config, show_config), bin/swarm.sh:ROLE_GROUPS and policy, bin/swarm.sh:codex_review, bin/lib/reports.sh:FINDING_REVIEWERS, bin/lib/build.sh:codex_rule, review_agent, docs/reference.md:fallback_reviewer row, codex paragraph, tests/fallback_reviewer_test.sh (new), tests/config_test.sh:CONFIG_KEYS, tests/roles_test.sh]
easy: false
estimate_lines: 270
---

# Every codex usage limit is logged, and with fallback_reviewer set a fallback agent reviews and its findings come back in codex's place

Builds on the split: codex_review (bin/swarm.sh:6814-6853) streams codex and parses nothing; review_agent and codex_rule in bin/lib/build.sh (:2500-2543, :2073-2081). On codex's usage-limit message, codex_review always logs incident `codex-limit`. A new key fallback_reviewer, empty (off) by default or a model name, is validated like builder_subagent_model (:183). With it set, codex_review starts a review agent on the same diff (new role review-fallback, on that model), waits for it as wait_agent does, prints its findings in codex's output form, and exits. Those findings are logged with reviewer fallback (FINDING_REVIEWERS, :776). codex_rule tells the builder to write 'reviewed by fallback <model>: codex usage limit' in the PR body. With the key empty, the output is today's 'codex skipped: usage limit'.

**Done when:**
- tests/fallback_reviewer_test.sh: a codex stub printing the usage-limit message, with fallback_reviewer = sonnet, starts the fallback agent (herdr stub) and the stub's findings appear in codex-review's stdout; with the key empty no agent starts, the output matches today's, and the incident line is written in both cases.
- The built brief's codex rule names 'reviewed by fallback' for the PR body (grep).
- tests/config_test.sh accepts fallback_reviewer and rejects a bad value; tests/roles_test.sh passes with review-fallback; `log-finding --reviewer fallback ...` is accepted.

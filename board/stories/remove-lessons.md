---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [recurring-kinds]
touches: [bin/swarm.sh:CONFIG_KEYS block (CFG defaults, CONFIG_KEYS, load_config, show_config), bin/swarm.sh:dispatch and usage header, bin/lib/reports.sh:lessons_report, LESSON_ constants, bin/lib/lessons_report.py, bin/lib/build.sh:project_rules, rule_kinds, rules_check_step, finding_rule, bin/lib/build.sh:story_brief, commands/swarm.md:collect step, docs/reference.md:lessons paragraphs, lessons_file row, README.md:lessons mention, tests/lessons_test.sh (delete), tests/removed_test.sh, tests/config_test.sh:CONFIG_KEYS, tests/epic_*_test.sh:finding_rule checks]
easy: false
estimate_lines: 240
---

# Remove lessons and its rule PRs; the collect step files a check story for each flagged kind

Needs recurring-kinds (outcomes' flagged kinds and the checks: key). Edits lessons_report (bin/lib/reports.sh, bin/swarm.sh:915) and its .py, LESSON_* (:767-769), rules_check_step and finding_rule's lesson lines (:2082-2105, 2378-2413) in bin/lib/build.sh, and lessons_file in the CONFIG_KEYS block (:149). Delete the rule-PR and brief-pruning code. commands/swarm.md's collect step (:70-82) becomes: read outcomes' flagged kinds and file one story with `checks: <kind>` per kind, which adds a test, lint rule, hook or review-prompt line. project_rules keeps pasting tagged rule lines into briefs, read from the brief and from AGENTS.md when the project has one, so swarm-dev's tagged rules still reach builders. A config with lessons_file loads silently until config-switch-ons removes the line. `swarm.sh lessons` keeps its dispatch arm and prints that recurring kinds are in outcomes, and exits 0. Most of the diff is deletions.

**Done when:**
- grep finds no LESSON_, rules_check_step or `lesson:` PR wording in bin/ or commands/ (tests/removed_test.sh), and commands/swarm.md's collect step names `checks:`.
- tests/config_test.sh: a config with lessons_file loads with no error or output; `swarm.sh lessons` prints the pointer and exits 0.
- A story brief built in a fixture project whose AGENTS.md has a tagged rule still contains that rule.
- Every tests/*_test.sh passes, with tests/lessons_test.sh deleted.

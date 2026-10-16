---
kind: code
status: ready
epic: leaner-faster-swarm
depends_on: []
touches: [bin/swarm.sh:cost_report, docs/method.md:§ Model and effort measure-before-tuning bullet, tests/cost_test.sh, tests/fixtures:cost sessions]
---

# `swarm.sh cost` counts every session in the project's directory, so the lead's own spend shows

cost_report (bin/swarm.sh:1013-1072) also reads each *.jsonl in the project's own directory under CLAUDE_PROJECTS (:707). Claude Code names that directory after the project path, with / and . turned into -. Each session there whose id is not in agents.tsv counts with role lead and kind claude. With --since, only the sessions whose first timestamp falls on or after that date count. The herdr-pane lead stays and is still counted once, because session ids and message ids dedupe. Put the code in cost_report's own python, not in REPORT_PY. dash's today figure reads cost_report through dash_slow and needs no change. docs/method.md: only the **Measure before tuning.** bullet of § Model and effort (:261-263). bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- tests/cost_test.sh: a fixture session in the project's encoded directory that agents.tsv does not name shows in a `lead` row, with its tokens and est. $. A session agents.tsv does name is counted once, under its own role.
- With --since a date after an unlisted session's first timestamp, that session is not counted.
- tests/dash_test.sh's check that today's cost equals `swarm.sh cost <today>` still passes.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.

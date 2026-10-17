---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/swarm.sh:dispatch and usage header, bin/swarm.sh:READ_ONLY_COMMANDS, bin/lib/reports.sh:dataset_report (new), bin/lib/dataset.py (new), bin/lib/report.py:rework_of, docs/reference.md:dataset row, README.md:commands list dataset, tests/dataset_test.sh (new), tests/events_test.sh:READ_ONLY list]
easy: false
estimate_lines: 260
---

# swarm.sh dataset writes one labelled JSON line per finished story

Builds on the split: story_text (a story's last version in git), outcomes rows, and rework_of() in bin/lib/report.py (model-fit-table's definition; add it if absent). A new command writes .swarm/dataset.jsonl, one line per finished story. Inputs are the story as planned, read from git at the board PR that added it: text, kind, risk, touches, depends_on, estimate_lines, easy, and planner_model (agents.tsv's lead for scope-<epic>). Results come from events.tsv, findings.tsv and git: diff lines and files, attempts, findings rounds, substantive findings, rework within 7 days, cost, minutes, every model that worked on it, and each escalation with its trigger. Escalate results are `ok (attempt N)`, or escalate-ladder-step-up's `ok (<trigger>: <from> -> <to>)`. A derived was_easy (merged on the first attempt, at most one findings round, no rework, a diff under 100 lines) carries was_easy_rule: 1. No environment, credentials or transcript text. prediction-scores reads this file.

**Done when:**
- tests/dataset_test.sh: fixture data for an easy-and-was-easy, an easy-but-was-hard and an escalated story gives three lines with the right inputs, results, models, trigger and was_easy; a planted env value and transcript line in the fixture logs appear nowhere in the output.
- The file is under .swarm/, and `git status` stays clean.

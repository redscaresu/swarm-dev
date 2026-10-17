---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [tests/doc_check_test.sh (new), tests/doc_check_known.txt (new)]
easy: false
estimate_lines: 150
---

# A doc check fails on any command, setting or path in the docs that swarm.sh does not have

Builds on the split: dispatch and CONFIG_KEYS in bin/swarm.sh. tests/doc_check_test.sh (so CI and make test run it) reads README.md, docs/*.md, commands/*.md, skills/ and templates/ for `swarm.sh <command>`, config keys in setting tables and repo paths. It fails on any that dispatch, CONFIG_KEYS or the tree lacks. A removed command that still prints a pointer passes by name. AGENTS.md, which only the lead edits, is not read. This story edits no doc. Each stale reference found today goes into tests/doc_check_known.txt (file and text, sorted by file), which the test allows. The docs-review stories empty that list, so it lands early and every later story keeps the docs in step.

**Done when:**
- tests/doc_check_test.sh passes on the branch, and fails on fixture docs naming `swarm.sh nosuch`, an unknown config key or a missing path that are not in the known list.
- The PR body lists every entry of tests/doc_check_known.txt.

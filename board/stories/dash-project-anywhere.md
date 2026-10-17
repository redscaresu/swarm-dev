---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/swarm.sh:main, bin/lib/dash.sh:dash args, tests/dash_projects_test.sh:temp-dir case]
easy: false
estimate_lines: 80
---

# dash --project runs from any directory

Builds on the split: main and find_project in bin/swarm.sh (:117-153, 6876), and dash's argument parse in bin/lib/dash.sh. 'not in a swarm project' comes from find_project, which runs for every command before dash sees --project. When the command is dash and every frame is named with --project, main skips the lookup. Not easy, because it touches the shared core.

**Done when:**
- tests/dash_projects_test.sh: `swarm.sh dash --project A --project B` run from a temp dir outside any project draws both frames; plain `swarm.sh dash` there still fails with 'not in a swarm project'.

---
kind: docs
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [llms.txt (new), .claude-plugin/plugin.json:description, keywords, skills/swarm-dev/SKILL.md:description, tests/llms_test.sh (new)]
easy: true
estimate_lines: 80
---

# llms.txt, plugin.json and the skill description tell an agent what swarm-dev is and when to use it

llms.txt at the repo root maps README.md, docs/method.md, docs/reference.md, docs/dash.md and commands/ in a few lines and names `swarm.sh init` and `/swarm-dev:swarm` as the first steps. plugin.json's description and keywords (version unchanged; today the description reads 'HLD → epics ...', plugin.json:4) and skills/swarm-dev/SKILL.md's description say what the plugin does and which request should trigger it, for the epic-first chain (/epic). The description lines in commands/*.md are docs-review-reference's.

**Done when:**
- tests/llms_test.sh: every path llms.txt names exists, it names swarm.sh init and /swarm-dev:swarm, plugin.json's description has no HLD, and its version is unchanged; `claude plugin validate .` passes.

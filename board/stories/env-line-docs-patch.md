---
kind: lead
status: ready
epic: dev-rules-docs
depends_on: []
touches: [AGENTS.md:Rules that are not negotiable, README.md:env line]
estimate_lines: 10
easy: true
---

# Lead: fix the stale env: line, and ship each loop fix as a patch release

The epic's Your part, the lead's own steps. The env: line at AGENTS.md:97-98 and README.md:127 (the epic's README.md:123-124 is stale) is still stale at 31ead5b. Land the docs patch in its own PR, matched to the agents' env allowlist in bin/lib/agents.sh; checklist-docs-line uses it as its example. From v0.29.0 on, cut a patch release soon after a fix to the swarm's own loop merges. The v0.29.0 cut is release-v0-29-0's.

**Done when:**
- A merged PR makes AGENTS.md's and README.md's env: lines say what bin/lib/agents.sh does; tests/doc_check_test.sh passes on it.

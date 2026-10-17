---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/build.sh:story_role, docs/reference.md:sonnet_share row, tests/sonnet_easy_test.sh (new)]
easy: true
estimate_lines: 60
---

# sonnet_share picks only stories marked easy: true

Builds on the split: story_role in bin/lib/build.sh (bin/swarm.sh:2424-2440; the epic's 2420-2435 is stale). The code-sonnet arm also requires `easy: true` in the story's front matter, and every other code story stays on code (Opus). docs (Sonnet) and chore (Haiku) keep their policy (:290-291). reference.md's sonnet_share row says so.

**Done when:**
- tests/sonnet_easy_test.sh: for sonnet_share 1 to 5, a story whose slug lands in the sample is code-sonnet only with easy: true, and code without it.

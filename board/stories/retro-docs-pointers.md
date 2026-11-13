---
kind: docs
status: blocked
epic: retro-report
depends_on: [retro-command]
needs: [retro-command (the retro dispatch arm; which doc_check needs before any doc names swarm.sh retro)]
touches: [README.md:Watching it (retro bullet), AGENTS.md:retro item (Useful while it runs; after the flow item :79), AGENTS.md:Never-run-in-a-loop rule (Working on this repository; :178-181)]
estimate_lines: 10
easy: true
---

# README.md and AGENTS.md name swarm.sh retro

Needs from retro-command: the retro arm, since doc_check fails on a doc that names a command with no arm. Add a README.md Watching it bullet (:98-102): `swarm.sh retro`, the lists a retro goes through with you before a minor release. In AGENTS.md, add a `swarm.sh retro [--since <tag>] [--memory <dir>]` line to the Useful while it runs list after the flow item (:79). Add `retro` to the never-loop rule (:178-181), run once after `gh api rate_limit` like flow. This is the only story in the epic that touches AGENTS.md. One sentence per line in docs (the coming 150-word line cap, board/stories/doc-line-cap.md).

**Done when:**
- README.md's Watching it list and AGENTS.md's Useful while it runs list each name `swarm.sh retro`. AGENTS.md's never-loop rule names retro beside flow, dash, outcomes and dataset.
- tests/doc_check_test.sh passes under scripts/select-tests.sh --run. The PR says the humanizer ran over the changed README.md and AGENTS.md lines.

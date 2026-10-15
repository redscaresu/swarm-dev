---
kind: docs
status: blocked
blocked_by: [codex-time-limit]
epic: flow-speedups
depends_on: [codex-time-limit]
touches: [docs/method.md (§ Who does what; § Building, **Review before closing.**), commands/hld.md (steps 4-5), commands/plan-hld.md (:53), commands/plan-epic.md (:87)]
---

# method.md: a board-only PR gets one codex pass plus the lead's own review, and the lead talks to agents through swarm.sh tell

One sentence in method.md § Building, **Review before closing.**: a PR that changes only board files (no code) gets one `swarm.sh codex-review` pass plus the lead's own reading, not repeated passes. 'open a PR through the codex loop' in commands/hld.md:48, plan-hld.md:53 and plan-epic.md:87 says the same. One sentence in method.md § Who does what: the lead's messages to agents go through `swarm.sh tell` (logged as tell:<kind>), never a bare `herdr agent prompt`. commands/hld.md:46 becomes `swarm.sh wait hld-<slug>`, then `swarm.sh tell hld-<slug> nudge <file>`, because tell refuses a busy agent and findings would set a goal.

**Done when:**
- `grep -n 'herdr agent prompt' commands/*.md` finds nothing, and commands/hld.md step 4 holds `swarm.sh tell hld-<slug> nudge`.
- `grep -n 'codex loop' commands/*.md` finds nothing. Each of hld.md, plan-hld.md and plan-epic.md names `codex-review` and one pass.
- docs/method.md contains 'board' and 'one' in **Review before closing.**, and `swarm.sh tell` with `herdr agent prompt` in § Who does what.
- humanizer ran over the changed README/docs/commands prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

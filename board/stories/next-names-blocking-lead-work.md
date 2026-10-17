---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [split-bash]
touches: [bin/lib/board.sh:next_step, commands/swarm.md, tests/next_test.sh]
easy: true
estimate_lines: 80
---

# `next` names ready lead stories that block an agent story, even while a conductor works

On 2026-10-17 `next` printed only `wait conduct-swarm-sh-split` for over an hour while board-prep, a ready `kind: lead` story, blocked agents-md-split-lines. The lead waited on the conductor and never saw it. When `next`'s step is `wait <conductor>`, it adds a line for each ready lead story that some blocked story `depends_on`: `also: lead <slug> blocks <slugs>`. commands/swarm.md tells the lead to run those stories while the wait runs in the background. dash's lead queue marks such a story `blocks <n>`.

**Done when:**
- On a fixture board with a working conductor, a ready lead story L, and a blocked story S with `depends_on: [L]`, `swarm.sh next` prints `wait conduct-<epic>` and then `also: lead L blocks S`.
- With no blocked story depending on L, no `also:` line prints.
- commands/swarm.md's `wait <agent>` step says to run each `also: lead` story while the wait runs; a grep in tests/next_test.sh checks it.

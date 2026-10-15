---
kind: code
status: ready
epic: flow-speedups
touches: [bin/swarm.sh:close_agent (paused and cleared-on-error), bin/swarm.sh:lead_block (reused), bin/swarm.sh:next_step, tests/close_test.sh, tests/next_test.sh, board/stories/README.md, templates/docs/stories/README.md]
---

# A story closed paused or cleared-on-error is held on the board, not only in a conductor's prompt

After #144, `swarm.sh close <slug> paused` and `close <slug> cleared-on-error` leave the story `ready` with nothing on the board. The "do not start it again; list it for the lead" hold lives only in the conductor's prompt, so a fresh conductor or `/swarm` run rebuilds it at once. close_agent puts a lead_block on those two causes, as it does for impossible: kind lead, escalated_from: <kind>, and the lead's choices (resume with `swarm.sh reset <slug> <reason>`, or drop), no **You:** step. attempts: is unchanged. next_step prints `escalated <slug>` for it.

**Done when:**
- tests/close_test.sh: `close s1 paused` and `close s1 cleared-on-error` on a ready code story with its builder open leave kind: lead, escalated_from: code, attempts unchanged and a lead block with no **You:** line; with no builder open, the story file is unchanged.
- tests/next_test.sh: after either close, `next` prints `escalated s1`, not `story s1`; after `reset s1 <reason>`, `next` offers it again.
- Both stories READMEs say so, and are identical in that paragraph.
- The PR shows each new check failing with the lead_block call removed; shellcheck and every tests/*_test.sh pass.

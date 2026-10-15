---
kind: code
status: ready
epic: flow-speedups
touches: [bin/swarm.sh:close_agent (paused and cleared-on-error), bin/swarm.sh:lead_block (reused), bin/swarm.sh:reset (held stories), bin/swarm.sh:next_step, tests/close_test.sh, tests/next_test.sh, board/stories/README.md, templates/docs/stories/README.md]
---

# A story closed paused or cleared-on-error is held on the board, not only in a conductor's prompt

After #144, `swarm.sh close <slug> paused` and `close <slug> cleared-on-error` leave the story `ready` with nothing on the board. The "do not start it again; list it for the lead" hold lives only in the conductor's prompt, so a fresh conductor or `/swarm` run rebuilds it at once. close_agent puts a lead_block on those two causes, as it does for impossible: kind lead, escalated_from: <kind>, held_for: <cause>, and a block naming the cause (paused, or the goal was cleared on an error) with the lead's choices (lift the hold with `swarm.sh reset <slug> <reason>`, or drop), no **You:** step. attempts: is unchanged. Lifting a hold is not the story's one reset: for a story with held_for:, reset puts the kind back and removes the block and held_for: but keeps attempts: and escalated_from: history as they were, and a later pause or error holds it again. next_step prints `escalated <slug>` with a reason naming the cause, never 'failed on Fable'.

**Done when:**
- tests/close_test.sh: `close s1 paused` and `close s1 cleared-on-error` on a ready code story with its builder open leave kind: lead, escalated_from: code, attempts unchanged and a lead block with no **You:** line; with no builder open, the story file is unchanged.
- tests/next_test.sh: after either close, `next` prints `escalated s1` and a reason containing 'paused' or 'cleared', and not 'Fable'; after `reset s1 <reason>`, `next` offers it again.
- tests/close_test.sh: a story with attempts: 1 is paused, reset, paused again and reset again: each reset succeeds, attempts: stays 1 throughout, and a later failed build still counts from there (the reset-once rule for failed Fable builds is unchanged).
- Both stories READMEs say so, and are identical in that paragraph.
- The PR shows each new check failing with the lead_block call removed; shellcheck and every tests/*_test.sh pass.

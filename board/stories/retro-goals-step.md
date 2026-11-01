---
kind: lead
status: ready
epic: board-loose-ends
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# Lead: put the Goals 1 to 14 reading into retro-report's retro-v0.31.0 story

The retro reading of Goals 1 to 14 is a step inside retro-report's retro-v0.31.0 lead story (epic Done when, line 22). That story is not on the board yet, because retro-report is not planned. Filed ready with no depends_on (depends_on retro-v0.31.0 would wait for the retro to finish, after this step was due); start it once retro-v0.31.0 is on the board. Then the lead adds this step by board PR, before that story's own You: steps: 'Goals 1 to 14: record each goal against its docs/features.tsv bar, from the flow sections its rows name (no pane read). Record the v0.30.0 build's flow as the second baseline (board/retros/v0.30.0.md). Record Goal 8's true reading: `swarm.sh dropped-lines redscaresu/swarm-dev <n> <head> <base>` (bin/swarm.sh:41) over every story PR merged since v0.30.0, one call per PR in sequence after `gh api rate_limit`. Write all of it as a `## Retro` section of board/retros/v0.31.0-checkpoint.md. **You:** read Goals 1 to 14 as recorded, and decide the deferred-findings and review_verify questions.' The same PR adds that section to the story's Done when. If retro-report's plan already wrote such a step, check it covers all of the above, add what is missing, and close this story.

**Done when:**
- retro-v0.31.0's story file on main, under whatever slug retro-report gives it, has the Goals 1 to 14 step with the dropped-lines rerun and the You: decision. Its Done when names the `## Retro` section of board/retros/v0.31.0-checkpoint.md.

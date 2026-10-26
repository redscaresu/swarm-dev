---
kind: code
status: ready
epic: review-loop
depends_on: []
touches: [bin/lib/lifecycle.sh:step_up_failed, tests/escalate_ladder_test.sh:failed step-up note cases]
estimate_lines: 110
easy: false
---

# A failed step-up tells the conductor through its inbox and wakes it

step_up_failed (bin/lib/lifecycle.sh:839-858) keeps the .step-up marker and logs step-up:failed, which wait --lead reports (#539). Add a note to the story's live conductor (conduct-<epic>, or the backlog conductor for a story with no epic). It names the story, the failure and `swarm.sh step-up --resume <slug>`. Send it through the `swarm.sh tell conduct-<epic> note <file>` path (tell_agent's note arm, agents.sh:1626-1636), never a direct inbox write, so note_wake runs and an idle conductor is prompted. With no live conductor, nothing is sent. A refusal inside the close (CLOSE_PANE_KEPT, marker removed) sends nothing.

**Done when:**
- tests/escalate_ladder_test.sh: a step-up fired by a tell from review-<slug>'s pane that fails after closing the builder keeps .swarm/briefs/<slug>.step-up, logs step-up:failed and a tell:note line for conduct-<epic>, and the note naming <slug> and step-up --resume is in its inbox.
- With that conductor idle (stubbed state), it gets the wake prompt (note_wake's 'Process your inbox now').
- With no conductor listed, nothing is sent and wait --lead still shows the failed step-up; a refusal inside the close sends nothing.

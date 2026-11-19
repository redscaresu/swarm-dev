---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [loop-exit, port-frame, bash-retired]
---

# Stage 4 ends, and v0.32 with it

The user has run the last version on their machines, and the stable ref moves to it.

Stage 4 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** The exit story records the differential run against v0.31.2 with each difference named (the fix: true stories', and the allow lists of stages 1 to 4), CI's wall time and process starts per command, and the three counts at zero outside the wrappers and scripts/: lines of bash, lines of Python and python3 start sites. The user has run the last v0.32.x on both Macs, agreed stage 4's allow list and said go. The stable ref is on it, and the second Mac, back on swarm-dev@swarm-dev, updated to it and ran `swarm.sh status` with python3 taken off PATH. The exit story and this epic have left the board, and the freeze is lifted.

**Out of scope:**
- Fixing what the exit finds: each is a new fix: true story
- The UI (v0.33)

**Constraints:**
- No stage: line.
- Exit rules X1 to X4 (shared_constraints.exit).
- Every stage ends on an exit epic holding one kind: lead story (HLD:352). The second pass kept stage 4's exit inside bash-retired, which also holds builds.
- No later stage names this epic, so its hold stops nothing. The user's go still comes before the stable ref moves (HLD:354-355,500-503).
- The check on the second Mac is goal 1 on a real machine: CI's test runs under stubs (rules.md:9).
- Rollback is the ref moved back and the sessions restarted (HLD:198-199).

**Your part:**
- Lead: record the last differential run, the speed figures and the three counts in the exit story.
- You switch the second Mac to swarm-dev@swarm-dev-pre for the trial, uninstalling swarm-dev@swarm-dev (HLD:70-73).
- You run the last version on both Macs, read the figures, agree stage 4's allow list, and say go: the story's You: step.
- Lead: move the stable ref after your go.
- You switch the second Mac back to swarm-dev@swarm-dev, uninstalling swarm-dev@swarm-dev-pre, and check that it updates.
- Lead: finish the exit story and then this epic (`swarm.sh finish`, a board PR each).
- Lead: lift the freeze on the board.
- Carve-out (HLD:480-485): none. The one story is kind: lead.

**Areas:**
- board/ (exit story)
- the stable ref
- the second Mac

**Shared rules cited above:**
- X1: One kind: lead story, with no PR and no after: line (HLD:352,359-360). The lead's steps around the user's go are steps of that story, or `next`'s own (the retro, the release), never stories of their own. The lead quotes the user's go, with its date, in the PR that finishes the story.
- X4: The order at an exit. (1) Every other epic of the stage has left the board, so no PR of the stage is still open. (2) The lead cuts the stage's last v0.32.x and reads the figures on that tag, then records them in the story. (3) The second Mac switches to swarm-dev@swarm-dev-pre: add `<repo>#pre-marketplace` if it is not there, install swarm-dev@swarm-dev-pre, uninstall swarm-dev@swarm-dev, restart its sessions. (4) The user runs the version on both Macs, agrees the stage's allow list and says go. (5) The second Mac switches back right after the go, before stable moves: install swarm-dev@swarm-dev, uninstall swarm-dev@swarm-dev-pre, restart its sessions. That installs the old stable. (6) The lead moves stable to the tag of step 2 and checks that stable and prerelease point where they should. (7) The second Mac updates with no other step, which checks that stable updates work. (8) The lead finishes the story and the epic. If the update on stable fails, the exit stays open and the fix is a fix: true story.

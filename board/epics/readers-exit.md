---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit, board-store, helpers-shared, helpers-ci-gate, helpers-dropped-lines, helpers-flow-queues, helpers-panes, helpers-reports, helpers-flow-reviews, port-board-readers, port-reports, port-release-gates, port-next, port-lead-queue-prs, port-lead-queue-agents, port-status]
---

# Stage 2 ends

The user has run the Go helpers and readers on their machines, the stable ref moves to them, and stage 3 can be planned.

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** No .py file is left under bin/lib, no inline `python3 -c` site imports a helper, and the 18 reader commands have markers. The exit story records the differential run against v0.31.2 with each difference named (the fix: true stories', and the allow lists of stages 1 and 2), CI's wall time and process starts per command before and after, and the lines of bash and Python and the python3 start sites left. The user has run it on both Macs, agreed stage 2's allow list and said go. The stable ref is on the stage's last v0.32.x, and the second Mac, back on swarm-dev@swarm-dev, updated to it and ran `swarm.sh status`. Until the exit story and this epic had left the board, `swarm.sh next` offered no stage 3 epic for planning; after, it does.

**Out of scope:**
- Fixing what the exit finds: each is a new fix: true story
- Any stage 3 work

**Constraints:**
- No stage: line.
- Exit rules X1 to X4 (shared_constraints.exit).
- Only v0.32.0 has a retro, so this is where the user looks before the loop is ported (HLD:437-438).
- The 18 are the HLD's 13 readers and base, lessons, cost, review-yield and features (contradiction 8).
- The patch that stable moves to passed the widened patch gate.
- Rollback is the ref moved back and the sessions restarted (HLD:198-199).

**Your part:**
- Lead: record the differential run, the speed figures and the three counts in the exit story.
- You switch the second Mac to swarm-dev@swarm-dev-pre for the trial, uninstalling swarm-dev@swarm-dev (HLD:70-73).
- You run the version on both Macs, read the figures, agree stage 2's allow list, and say go: the story's You: step.
- Lead: move the stable ref after your go.
- You switch the second Mac back to swarm-dev@swarm-dev, uninstalling swarm-dev@swarm-dev-pre, and check that it updates.
- Lead: finish the exit story and then this epic (`swarm.sh finish`, a board PR each). Stage 3 is planned only after both have merged.
- Lead and you: after each update, run `swarm.sh version` once before other work.
- Carve-out (HLD:480-485): none. The one story is kind: lead.

**Areas:**
- board/ (exit story)
- the stable ref
- the second Mac

**Shared rules cited above:**
- X1: One kind: lead story, with no PR and no after: line (HLD:352,359-360). The lead's steps around the user's go are steps of that story, or `next`'s own (the retro, the release), never stories of their own. The lead quotes the user's go, with its date, in the PR that finishes the story.
- X4: The order at an exit. (1) Every other epic of the stage has left the board, so no PR of the stage is still open. (2) The lead cuts the stage's last v0.32.x and reads the figures on that tag, then records them in the story. (3) The second Mac switches to swarm-dev@swarm-dev-pre: add `<repo>#pre-marketplace` if it is not there, install swarm-dev@swarm-dev-pre, uninstall swarm-dev@swarm-dev, restart its sessions. (4) The user runs the version on both Macs, agrees the stage's allow list and says go. (5) The second Mac switches back right after the go, before stable moves: install swarm-dev@swarm-dev, uninstall swarm-dev@swarm-dev-pre, restart its sessions. That installs the old stable. (6) The lead moves stable to the tag of step 2 and checks that stable and prerelease point where they should. (7) The second Mac updates with no other step, which checks that stable updates work. (8) The lead finishes the story and the epic. If the update on stable fails, the exit stays open and the fix is a fix: true story.

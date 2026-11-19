---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit, port-wait-agent, port-wait-pr, port-agent-starts, port-board-pr, port-board-writers, port-release, port-tell, port-story, port-close, port-merge-base, port-reconcile, port-review-agent, port-conduct, port-step-up, port-merge, port-lead-wait, port-upgrade, lead-wait-fixes, port-guard, port-hooks]
---

# Stage 3 ends

The swarm runs on its own Go loop, the user has run it, the stable ref moves to it, and stage 4 can be planned.

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** All 50 commands have markers, and the five hooks and the gh shim are wrappers. No `_` name is left that only hands a Go command's work to bash. The 15 folded and deferred items in this plan have merged, each after its command's port. The exit story records the differential run against v0.31.2 with each difference named (the fix: true stories', and the allow lists of stages 1 to 3), CI's wall time and process starts per command, and the three counts. On the lead's machine the swarm has built, reviewed and merged one whole story with every loop command in Go. The user has run it on both Macs, agreed stage 3's allow list and said go. The stable ref is on the stage's last v0.32.x, and the second Mac, back on swarm-dev@swarm-dev, updated to it and ran a story. Until the exit story and this epic had left the board, `swarm.sh next` offered no stage 4 epic for planning; after, it does.

**Out of scope:**
- Fixing what the exit finds: each is a new fix: true story
- Moving the frame and removing the last bash (port-frame, bash-retired)

**Constraints:**
- No stage: line.
- Exit rules X1 to X4 (shared_constraints.exit).
- The loop's ports ship with no retro, so this exit is the user's look before other machines get them (HLD:437-438).
- Rollback is the ref moved back and the sessions restarted, which rolls the hooks back too (HLD:198-199).

**Your part:**
- Lead: record the differential run, the speed figures and the three counts in the exit story.
- You switch the second Mac to swarm-dev@swarm-dev-pre for the trial, uninstalling swarm-dev@swarm-dev (HLD:70-73).
- You run the version on both Macs, read the figures, agree stage 3's allow list, and say go: the story's You: step.
- Lead: move the stable ref after your go.
- You switch the second Mac back to swarm-dev@swarm-dev, uninstalling swarm-dev@swarm-dev-pre, and check that it updates.
- Lead: finish the exit story and then this epic (`swarm.sh finish`, a board PR each). Stage 4 is planned only after both have merged.
- Lead and you: after each update, run `swarm.sh version` once before other work, so the guard has its binary.
- Carve-out (HLD:480-485): none. The one story is kind: lead.

**Areas:**
- board/ (exit story)
- the stable ref
- the second Mac

**Shared rules cited above:**
- X1: One kind: lead story, with no PR and no after: line (HLD:352,359-360). The lead's steps around the user's go are steps of that story, or `next`'s own (the retro, the release), never stories of their own. The lead quotes the user's go, with its date, in the PR that finishes the story.
- X4: The order at an exit. (1) Every other epic of the stage has left the board, so no PR of the stage is still open. (2) The lead cuts the stage's last v0.32.x and reads the figures on that tag, then records them in the story. (3) The second Mac switches to swarm-dev@swarm-dev-pre: add `<repo>#pre-marketplace` if it is not there, install swarm-dev@swarm-dev-pre, uninstall swarm-dev@swarm-dev, restart its sessions. (4) The user runs the version on both Macs, agrees the stage's allow list and says go. (5) The second Mac switches back right after the go, before stable moves: install swarm-dev@swarm-dev, uninstall swarm-dev@swarm-dev-pre, restart its sessions. That installs the old stable. (6) The lead moves stable to the tag of step 2 and checks that stable and prerelease point where they should. (7) The second Mac updates with no other step, which checks that stable updates work. (8) The lead finishes the story and the epic. If the update on stable fails, the exit stays open and the fix is a fix: true story.

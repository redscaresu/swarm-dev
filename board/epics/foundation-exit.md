---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [ship-gates, go-module, port-inventory, port-checks, go-layers, binary-wrapper, release-ci, binary-fetch, release-client, first-port]
---

# Stage 1 ends

v0.32.0 is on the prerelease ref and the lead's machine runs it. Once the user says go the stable ref moves, so every machine gets it, and stage 2 can be planned.

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** v0.32.0 is tagged with four binaries, checksums and an attestation, and the prerelease ref is on it. The lead's machine has only swarm-dev@swarm-dev-pre installed, and its swarm.sh runs the downloaded, checked binary. The exit story records the differential run against v0.31.2 with each difference named (the fix: true stories', and stage 1's allow list), CI's wall time and process starts per command, and the lines of bash and Python and the python3 start sites left. The retro file records that the v0.31.0 test-speed items move to v0.33. The user has run it on both Macs, agreed stage 1's allow list and said go. The stable ref is on v0.32.0, and the second Mac, back on swarm-dev@swarm-dev, updated to it with no other step and ran a command. Until the exit story and this epic had left the board, `swarm.sh next` offered no stage 2 epic for planning; after, it does.

**Out of scope:**
- Fixing what the exit finds: each is a new fix: true story
- Any stage 2 work

**Constraints:**
- No stage: line, or the release it cuts could never be offered: contradiction 5.
- Exit rules X1 to X4 (shared_constraints.exit).
- v0.32.0 is a minor: it needs a done board/retros/v0.32.0.md, and `next` prints `retro v0.32.0` first (docs/reference-merging.md:1158-1176). The retro and the release are `next`'s steps, not stories.
- The release PR is a version bump only, cut with `swarm.sh merge --release`. Its docs gate needs README.md, AGENTS.md and docs/ in line with everything since v0.31.2.
- The lead's switch to prerelease uninstalls swarm-dev@swarm-dev, or the hooks load twice (HLD:204-205,455-456).
- The second Mac switches to swarm-dev@swarm-dev-pre for the trial and back once stable moves, which also checks that stable updates (HLD:70-73).
- Rollback is the ref moved back and the sessions restarted (HLD:198-199), as release-ci proved it.

**Your part:**
- You and the lead go through the v0.32.0 retro.
- Lead: record in the v0.32.0 retro that the v0.31.0 test-speed items move to v0.33 (HLD:495-497; board/retros/v0.31.0.md:22,49,54).
- Lead: cut v0.32.0 with `swarm.sh merge --release`.
- Lead: add the pre-marketplace marketplace, install swarm-dev@swarm-dev-pre, uninstall swarm-dev@swarm-dev, restart the sessions.
- Lead: record the differential run, the speed figures and the three counts in the exit story.
- You switch the second Mac to swarm-dev@swarm-dev-pre for the trial, uninstalling swarm-dev@swarm-dev (HLD:70-73).
- You run v0.32.0 on both Macs, read the differential run and the speed figures, agree stage 1's allow list, and say go: the story's You: step.
- Lead: move the stable ref to v0.32.0 after your go.
- You switch the second Mac back to swarm-dev@swarm-dev, uninstalling swarm-dev@swarm-dev-pre, and check that it updates.
- Lead: finish the exit story and then this epic (`swarm.sh finish`, a board PR each). Stage 2 is planned only after both have merged.
- Lead and you: after each update, run `swarm.sh version` once before other work, so the binary is there.
- Carve-out (HLD:480-485): none. The one story is kind: lead.
- Lead: after the v0.32.0 cut, check by hand the four assets, their checksums, the attestation and the prerelease ref. After switching to swarm-dev@swarm-dev-pre, run `swarm.sh upgrade` in each project with agents before restarting the sessions: the cut's own merge --release updated swarm-dev@swarm-dev on stable and moved no agent (critic).

**Areas:**
- board/ (retro, exit story)
- .claude-plugin/plugin.json (version)
- the stable and prerelease refs
- the lead's machine and the second Mac

**Shared rules cited above:**
- X1: One kind: lead story, with no PR and no after: line (HLD:352,359-360). The lead's steps around the user's go are steps of that story, or `next`'s own (the retro, the release), never stories of their own. The lead quotes the user's go, with its date, in the PR that finishes the story.
- X4: The order at an exit. (1) Every other epic of the stage has left the board, so no PR of the stage is still open. (2) The lead cuts the stage's last v0.32.x and reads the figures on that tag, then records them in the story. (3) The second Mac switches to swarm-dev@swarm-dev-pre: add `<repo>#pre-marketplace` if it is not there, install swarm-dev@swarm-dev-pre, uninstall swarm-dev@swarm-dev, restart its sessions. (4) The user runs the version on both Macs, agrees the stage's allow list and says go. (5) The second Mac switches back right after the go, before stable moves: install swarm-dev@swarm-dev, uninstall swarm-dev@swarm-dev-pre, restart its sessions. That installs the old stable. (6) The lead moves stable to the tag of step 2 and checks that stable and prerelease point where they should. (7) The second Mac updates with no other step, which checks that stable updates work. (8) The lead finishes the story and the epic. If the update on stable fails, the exit stays open and the fix is a fix: true story.

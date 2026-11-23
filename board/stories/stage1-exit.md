---
kind: lead
status: ready
epic: foundation-exit
depends_on: []
touches: [board/stories/stage1-exit.md]
estimate_lines: 0
easy: true
---

# Lead: stage 1's exit, from the v0.32.0 cut to stable on it

The one story of foundation-exit (X1): no PR of its own and no after: line. The retro and the release are `next`'s steps around it, never stories. Follow the epic's X4 order.

1. Lead: once `next` prints `retro v0.32.0`, go through the report with the user and land board/retros/v0.32.0.md (covers: v0.31.3..v0.32.0, done: set) by board PR. It records that the v0.31.0 test-speed items move to v0.33.
2. Lead: once `next` prints `release`, cut v0.32.0 with `swarm.sh merge --release`, a version bump only, with README.md, AGENTS.md and docs/ in line with everything since v0.31.3. Check by hand the four assets, SHA256SUMS, the attestation and that prerelease points at v0.32.0.
3. Lead: add `redscaresu/swarm-dev#pre-marketplace` if it is missing, install swarm-dev@swarm-dev-pre, then run the prerelease install's `swarm.sh upgrade` in each project with agents, so they move to v0.32.0 and not to the stable path. Then uninstall swarm-dev@swarm-dev and restart the sessions (docs/lead-by-hand.md § Switching to the prerelease). Run `swarm.sh version` once.
4. Lead: record here the differential run against v0.31.2 (each difference named: the fix: true stories' and stage 1's allow list), CI's wall time and process starts per command from the speed job, and the lines of bash and Python and the python3 start sites left.
5. **You:** switch the second Mac to swarm-dev@swarm-dev-pre (the same steps as 3), uninstalling swarm-dev@swarm-dev.
6. **You:** run v0.32.0 on both Macs, read the figures in step 4, agree stage 1's allow list and say go.
7. **You:** right after the go, switch the second Mac back: install swarm-dev@swarm-dev, uninstall swarm-dev@swarm-dev-pre, restart its sessions.
8. Lead: move stable to v0.32.0 and check that stable and prerelease both point at it.
9. **You:** update the second Mac with no other step, and run one command. If the update fails, the exit stays open and the fix is a fix: true story.
10. Lead: quote the user's go with its date, then `swarm.sh finish stage1-exit` and `swarm.sh finish foundation-exit`, a board PR each.

**Done when:**
- v0.32.0 is tagged with four binaries, SHA256SUMS and an attestation, and stable and prerelease are on it.
- board/retros/v0.32.0.md is on main with covers: and done: set and the v0.33 test-speed line.
- This file records the differential run, the speed figures and the three counts, and quotes the user's dated go.
- The second Mac updated on stable with no other step and ran a command.

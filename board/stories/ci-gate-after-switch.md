---
kind: lead
status: later
epic: helpers-ci-gate
depends_on: [ci-gate-switch]
needs: ci-gate-switch: its merge to main, which the patch carries and whose board-only.sh the next PRs are judged by.
touches: []
estimate_lines: 0
risk: high
---

# Lead: ship the switch to the prerelease ref and check CI's gate on the PRs after it

Needs ci-gate-switch merged. No builder runs it; it is the lead's L2 for the one patch that changes what runs.
1. Lead: before the patch, check that stable and prerelease point at their expected tags (L2).
2. Lead: once main's CI on the switch's merge is green and `swarm.sh next` prints release, cut the v0.32.x patch through /swarm-dev:swarm's release arm (`swarm.sh merge --release`). Its PR is a version-only bump on main's tip, judged by the new base copy of board-only.sh, so it is the first real run of the binary in CI's gate.
3. Lead: after the patch, check both refs again (L2), and run `swarm.sh version` in the lead's sessions.
4. Lead: on the first PR after the switch whose tests run, check that test-shard passed board_only_test.sh.
5. Lead: if the swarm stalls on the Go (a merge, wait-pr, review agent or watch that hangs or misjudges a head), revert or fix the port on main, move prerelease back and restart the sessions (L2; HLD:433-436), and log it with `swarm.sh intervene`.
The lead quotes the gate lines, the refs and the test result in the PR that finishes this story.

**Done when:**
- (1) In each of the patch release PR's seven gated jobs, the gate step prints `board-only: true (a version-only release on main's latest, green commit)`, quoted. (2) git ls-remote shows stable and prerelease on their expected tags before and after the patch, quoted. (3) The first PR after the switch whose tests ran passed board_only_test.sh, linked. (4) Either no stall, or the rollback's ref move and restart are recorded.

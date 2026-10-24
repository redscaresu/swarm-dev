---
kind: docs
status: ready
depends_on: []
touches: [commands/swarm.md:release arm, tests/swarm_md_test.sh]
estimate_lines: 30
easy: true
---

# /swarm-dev:swarm uses the release grant

release-grant-gate (#428) lets `merge --release` take a release from the lead under `merge = human` when HLDs granting `release` cover every story since the tag. But commands/swarm.md's release arm (around :285) still tells the lead, under `merge = human`, to hand the bump PR to the user and stop. So the grant never fires through `/swarm-dev:swarm` (conduct-hld-grants report, 2026-10-24).

- In the release arm, under `merge = human`: run `swarm.sh merge --release --head <sha> <url>` as under `agent`. If it refuses for the release grant, do what the arm does today: keep the worktree and branch, tell the user the PR waits on them, and stop. Any other refusal is handled as under `agent`.
- If no test greps commands/swarm.md's release arm yet, add the grep to the closest existing test (`grep -rln "commands/swarm.md" tests`) and fix `touches` in the PR.

**Done when:**
- A test asserts the release arm runs `merge --release` under `merge = human` and stops only on its release-grant refusal.
- `make test` passes.

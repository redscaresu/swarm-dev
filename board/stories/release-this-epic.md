---
kind: lead
status: blocked
blocked_by: [plan-during-review-and-release]
epic: leaner-faster-swarm
depends_on: [plan-during-review-and-release]
touches: []
---

# The lead cuts the release that carries this epic

This is the epic's last step. Once every agent story of this epic has merged (method-guide-and-reference and readme-and-agents last), the lead runs /swarm-dev:swarm in swarm-dev, and `swarm.sh next` prints `release`, because main has changes since the last v<version> tag. The lead follows commands/swarm.md's release arm: a minor bump of .claude-plugin/plugin.json in its own PR (this epic adds commands), merged with `swarm.sh merge --release`, since swarm-dev is merge = agent. Then it checks what was published. The story depends only on plan-during-review-and-release, which builds the release step. Waiting for the docs stories is `next`'s job: it prints `release` only after its build, plan and escalated steps, so not while a conductor runs or a story of the epic is ready. That keeps the chain 3 deep. **You:** none.

**Done when:**
- This story quotes `swarm.sh next` printing `release` after the epic's last agent story merged.
- The release PR changed only .claude-plugin/plugin.json, to the next minor version, merged through `swarm.sh merge --release`, and is linked here.
- The tag v<new> exists, every merge commit of this epic's PRs is an ancestor of it (`git merge-base --is-ancestor`, output posted here), and `gh release view v<new>` shows the release published.

---
kind: lead
status: blocked
blocked_by: [plan-during-review-and-release, merge-holds-costs-money, reconcile-always-pulls]
epic: leaner-faster-swarm
depends_on: [plan-during-review-and-release, merge-holds-costs-money, reconcile-always-pulls]
touches: []
---

# The lead cuts the release that carries this epic

This is the epic's last step. Once every agent story of this epic has merged (method-guide-and-reference and readme-and-agents last), the lead runs /swarm-dev:swarm in swarm-dev, and `swarm.sh next` prints `release`, because main has changes since the last v<version> tag. The lead follows commands/swarm.md's release arm: a minor bump of .claude-plugin/plugin.json in its own PR (this epic adds commands), merged with `swarm.sh merge --release`, since swarm-dev is merge = agent. Then it checks what was published. The story depends only on plan-during-review-and-release, which builds the release step. Waiting for the docs stories is `next`'s job: it prints `release` only after its build, plan and escalated steps, so not while a conductor runs or a story of the epic is ready. That keeps the chain 3 deep. **You:** none.

**Done when:**
- Before the release PR, the lead reads README.md, docs/ and the diagrams in docs/assets as a newcomer would (user, 2026-10-17: "think about what a human really needs to understand our project and to get started immediately"). The README answers in its first screen what swarm-dev is, what you need (Claude Code, herdr, gh), and the three commands to go from nothing to a first merged story. Anything a newcomer does not need on day one moves to docs/ or is deleted. A diagram that no longer matches the flow (no verify kind, no epic PRs, no release stories) is redrawn or removed. The fixes merge as their own docs PR, linked here, before the release PR.
- This story quotes `swarm.sh next` printing `release` after the epic's last agent story merged.
- The release PR changed only .claude-plugin/plugin.json, to the next minor version, merged through `swarm.sh merge --release`, and is linked here.
- The tag v<new> exists, every merge commit of this epic's PRs is an ancestor of it (`git merge-base --is-ancestor`, output posted here), and `gh release view v<new>` shows the release published.

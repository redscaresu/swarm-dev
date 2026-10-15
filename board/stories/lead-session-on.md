---
kind: lead
status: blocked
blocked_by: [dash-tells-the-truth-release]
epic: dash-tells-the-truth
depends_on: [dash-tells-the-truth-release]
touches: [.claude/swarm/config, infrafactory: .claude/swarm/config]
---

# Turn lead = session on in swarm-dev, then in infrafactory through its own board PR

After the release merges. An installed swarm.sh that predates the key dies on any project whose config names it (load_config's unknown-key arm, bin/swarm.sh:193), so the update comes first. the lead run `claude plugin update swarm-dev@swarm-dev`, restart Claude Code and say go. The lead adds `lead = session` to swarm-dev's .claude/swarm/config in a board PR (the config is tracked and lead-only), checks `swarm.sh config lead` prints session and `swarm.sh dash` draws the lead's queue box. Then the same line in infrafactory's .claude/swarm/config through infrafactory's own board PR, with the same two checks there.

**Done when:**
- `swarm.sh config lead` prints `session` in swarm-dev and in infrafactory, each from a merged board PR. `swarm.sh dash` in each draws without error, and any merge, lead-story-without-You, empty-pane or stalled row it shows sits in the lead's queue box.

**From review (binding; overrides the scope above where they differ):**
- Nothing waits on the user: the lead runs `claude plugin update swarm-dev@swarm-dev`, checks the installed swarm.sh accepts `lead`, then turns it on in swarm-dev's config by PR and in infrafactory's via its own board PR, and merges both.

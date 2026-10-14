---
kind: chore
status: blocked
blocked_by: [release-agent-state, skill-swarm-dev, cold-start-swarm-first-run, cold-start-fresh-session, cold-start-swarm-resolves]
epic: cold-start
depends_on: [release-agent-state, skill-swarm-dev, cold-start-swarm-first-run, cold-start-fresh-session, cold-start-swarm-resolves]
touches: [.claude-plugin/plugin.json]
---

# Bump plugin.json once for the cold-start release

Bump `version` in .claude-plugin/plugin.json to the next minor of whatever main holds when the story starts. Do not hardcode it: release-agent-state takes it to 0.14.0 (board/stories/release-agent-state.md:11), and build-outcomes and sonnet-share bump it too (build-outcomes.md:5, sonnet-share.md:5). If another bump merged after skill-swarm-dev or cold-start-swarm-first-run, say in the PR that cold-start shares that release. The PR body lists what ships: the skill, /swarm's brief question and empty-board text, README. The user merges (merge = human), and release.yml publishes v<version>. No README change: no prose a user reads changes. Run humanizer over the PR description, and say so.

**Done when:**
- The diff is one line in .claude-plugin/plugin.json, and its version is greater than main's at the PR's base.
- `git log` between the previous version bump on main and this PR's base contains skill-swarm-dev's and cold-start-swarm-first-run's merges, and no other version bump; otherwise the PR says which release cold-start shipped in.
- `claude plugin validate .` and every tests/*_test.sh pass; the PR says humanizer ran over its description.

**From review (binding; overrides the scope above where they differ):**
- Version is the next minor of main's at the PR's base.
- No other story bumps plugin.json (build-outcomes and sonnet-share no longer do), so cold-start ships only here. If a bump nonetheless merged after both wave-1 stories, open no PR, record on this story which v<version> carried cold-start, and finish.

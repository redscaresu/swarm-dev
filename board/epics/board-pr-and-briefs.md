---
status: active
parent: less-noise
hld: 2026-10-25-swarm-dev-0-28
stage: v0.29.0
depends_on: []
---

# Quieter board PRs, waits and briefs

Board PRs of three kinds skip codex, no incident or nudge for a working agent, briefs show the guard's forms and the test lines, and moved checks stop counting as unchecked.

A child of less-noise, split at planning (2026-10-26). Its stories were planned with the parent; the parent's Out of scope, Constraints and Your part apply.

**Done when:**
- board-pr-kinds: Board PRs of kind story-scope edit, hold or finish land with no codex-review
- no-busy-timeout-incident: A wait that times out on a working agent logs no incident
- no-nudge-to-busy: Nobody sends a nudge to an agent that is still working
- builder-test-lines: Builder brief: selected tests after review fixes, and no self-matching pgrep
- guard-forms-brief: Briefs show the command forms the guard accepts and forms that need no approval
- moved-checks-not-unchecked: rules-unchecked skips a check moved from one file to another

**Areas:** see each story's touches.

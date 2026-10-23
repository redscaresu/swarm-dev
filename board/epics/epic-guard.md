---
status: active
parent: retro-and-shared-rules
depends_on: [hld-grants]
check: make test
---

# No epic goes active without a ticket, and a project can let the lead activate its own

The parent's goals 4 and 5.

**Done when:**
- `swarm.sh merge --board` and `board-pr open` refuse a PR whose diff adds an `epics/*.md` as `status: active`, or flips one from `draft` to `active`, unless the epic at the PR's head has one of these:
  - an `agreed: <date>` line;
  - an `hld:` naming an agreed HLD that grants `epics`;
  - a `parent:`;
  - the project's `lead_epics = on`.
  
  The refusal names the epic and says to run `/swarm-dev:epic <slug>`. A `later` to `active` flip passes, and so does a PR that changes no epic's status. Stub-gh tests in tests/merge_test.sh cover each ticket, the refusal and both passes.
- commands/epic.md step 5 writes `agreed: <YYYY-MM-DD>` into the front matter when it sets `status: active`.
- `lead_epics` (default `off`) is a key in `.claude/swarm/config`, and `swarm.sh config lead_epics` prints it. commands/swarm.md and skills/swarm-dev/SKILL.md say the lead never sets an epic active without a grant, the key or the user.

**Out of scope:** migrating epics already active. The guard reads the diff, not history.
**Constraints:** the parent's. The guard ships on, as the user asked, and `lead_epics` is its off switch per project.
**Your part:** none.

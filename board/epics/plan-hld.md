---
status: active
parent: retro-and-shared-rules
depends_on: [hld-grants]
check: make test
---

# An agreed HLD is decomposed into epics by a swarm, and the chain carries on

The parent's goal 3, and the `epics` grant's prompt half of goal 2.

**Done when:**
- An HLD has epics when an `epics/*.md` on the board carries `hld: <its file name>`. `swarm.sh next` prints `plan-hld <hld>` for an agreed HLD with none. It never prints it for a `draft` or `superseded` HLD. A test covers all three cases.
- `/plan-hld <hld>` (`commands/plan-hld.md`) runs survey, decompose, skeptics, codex and critic, as before #293 (45b2af1a^). Each epic it writes carries `hld:`, and the HLD's `## Epics` links it. Using hld-grants' reader, with `epics` in the HLD's `grants:`, the epics are written `status: active` and the board PR opens without asking. Without it, each epic is a `draft` the user agrees through `/epic`.
- The `hld-lead` role is in `ROLE_GROUPS` with `policy hld-lead` answering `claude fable xhigh`, and tests/removed_test.sh drops its `plan-hld`, `hld-lead` and commands/plan-hld.md assertions.
- hooks/lead-stop.sh enforces `plan-hld` as it does `plan-epic` (hooks/lead-stop.sh:181-188). A test covers it.
- `swarm.sh finish <hld>` opens the board PR that deletes an HLD once every epic with its `hld:` has left the board, and refuses while one is left.
- commands/swarm.md has a `plan-hld <hld>` step and an `hld <hld>` step. dash's `hld` walk (bin/lib/dash.sh:542) and board/Board.base read the same statuses.

**Out of scope:** the epic guard (epic-guard), user docs (hld-docs).
**Constraints:** the parent's.
**Your part:** none.

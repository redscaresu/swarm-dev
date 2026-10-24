---
status: active
parent: retro-and-shared-rules
depends_on: [hld-grants]
check: make test
---

# An agreed HLD is decomposed into epics by a swarm, and the chain carries on

The parent's goal 3, and the `epics` grant's prompt half of goal 2.

**Done when:**
- An HLD has been planned when its front matter carries `planned: <date>`, which /plan-hld's board PR sets. `swarm.sh next` prints `plan-hld <hld>` for an agreed HLD with no `planned:`, and `hld <hld>` (finish it) for a planned HLD with no epic left carrying `hld: <its file name>`. It never prints either for a `draft` or `superseded` HLD. A test covers each case.
- `/plan-hld <hld>` (`commands/plan-hld.md`) runs survey, decompose, skeptics, codex and critic, as before #293 (45b2af1a^). Each epic it writes carries `hld:`, and the HLD's `## Epics` links it. Using hld-grants' reader, with `epics` in the HLD's `grants:`, the epics are written `status: active` and the board PR opens without asking. Without it, each epic is a `draft` the user agrees through `/epic`.
- The `hld-lead` role is in `ROLE_GROUPS` with `policy hld-lead` answering `claude fable xhigh`, and tests/removed_test.sh drops its `plan-hld`, `hld-lead` and commands/plan-hld.md assertions.
- hooks/lead-stop.sh enforces `plan-hld` as it does `plan-epic` (hooks/lead-stop.sh:181-188). A test covers it.
- `swarm.sh finish <hld>` opens the board PR that deletes a planned HLD once every epic with its `hld:` has left the board, and refuses while one is left or while it has no `planned:`.
- Under `merge = human`, an HLD that grants `merge` covers /plan-hld's board PR, which changes only that HLD's `planned:` line and `## Epics` section and adds epics carrying its `hld:`. The finish PR stays the user's.
- commands/swarm.md has a `plan-hld <hld>` step and an `hld <hld>` step. dash's `hld` walk (bin/lib/dash.sh:542) and board/Board.base read the same statuses.

**Checks before every stage:** run tests as `env -u SWARM_PROJECT make test TESTS=... JOBS=4`, never `bash` a test file; shellcheck and py_compile as AGENTS.md lists; bash 3.2 only; the loose_match lint (an exact match on any slug or `hld:` value: `[[ == ]]`, `grep -Fx`); the timeouts lint for herdr, curl and `gh run` calls; no gh in next_step. The lead cuts no release while next-plan-hld has merged and plan-hld-command has not: `next` would name a step with no command.

**Out of scope:** the epic guard (epic-guard), user docs (hld-docs).
**Constraints:** the parent's.
**Your part:** none.

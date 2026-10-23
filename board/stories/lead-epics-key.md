---
kind: code
status: ready
epic: epic-guard
depends_on: []
touches: [bin/swarm.sh:CFG defaults, CONFIG_KEYS and load_config, docs/method.md:config table, docs/reference.md:Settings, tests/config_test.sh]
estimate_lines: 30
easy: true
---

# lead_epics (default off) is a config key, and swarm.sh config lead_epics prints it

In bin/swarm.sh:
- Add `CFG_lead_epics=off` beside CFG_merge_admin (:193).
- Add `lead_epics` to CONFIG_KEYS (:195).
- Add a load_config arm like merge_admin's (:234-235). It dies with `<file>:<line>: lead_epics must be off or on, not '<v>'`.

show_config needs nothing more (:268-269).

Add one row to docs/method.md's config table after merge_admin (:137). The row says only what the key is: `on` lets the lead set an epic active on its own, and `off` lets an epic go active only through the user or a grant. Don't mention the guard. epic-guard-board-pr adds that clause when the guard lands. Add the same key line to docs/reference.md § Settings. README lists no config keys, so it needs nothing.

Nothing reads the key yet, so no behaviour changes. This is this epic's only edit to bin/swarm.sh; plan-hld edits ROLE_GROUPS and policy there. Run the humanizer over the new prose.

**Done when:**
- tests/config_test.sh has three cases, modelled on :140-145:
  - `lead_epics ships off`: `swarm.sh config lead_epics` prints off.
  - `lead_epics = on is read`.
  - `lead_epics = yes` is refused, naming file:line.
- The three-key-list check (:179-198) passes with the new table row.
- `make test` passes.

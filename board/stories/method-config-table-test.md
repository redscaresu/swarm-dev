---
kind: code
status: blocked
blocked_by: [infrafactory-epic-on-agent-state]
epic: fable-on-call
depends_on: [infrafactory-epic-on-agent-state]
touches: [tests/config_test.sh (new table block)]
---

# A test that the method's config table, CONFIG_KEYS and load_config name the same keys

Test only, in tests/config_test.sh. Read the key column of the table in docs/method.md § Configuring a project (:121-135), CONFIG_KEYS (bin/swarm.sh:138) and load_config's case arms (:155-183), and fail naming each key missing from any of the three. No swarm.sh or method change: 13 rows and 13 keys agree today, so it passes on main. It must merge before wire-escalate-role adds escalate_after (epic:17).

**Done when:**
- tests/config_test.sh passes on the PR head.
- The PR shows it failing, naming the key, on three planted edits: a table row deleted, a key added to CONFIG_KEYS only, a load_config arm renamed.
- shellcheck tests/*.sh and every tests/*_test.sh pass.

**From review (binding; overrides the scope above where they differ):**
- Runs on macOS's bash 3.2: no mapfile, no associative arrays (AGENTS.md).

---
kind: code
status: ready
epic: binary-wrapper
depends_on: []
touches: [tests/swarm_commands.sh (new), tests/doc_check_test.sh:doc_check commands and keys, tests/skill_test.sh:is_command, tests/port_names_test.sh:arms, tests/events_test.sh:arms read]
estimate_lines: 130
---

# doc_check, skill_test, port_names and events read the commands from dispatch and the markers, and fail on none

Needs no other story; tests only. Four tests read the command list from bin/swarm.sh's text, each its own way: doc_check's python (tests/doc_check_test.sh:36-39), port_names' python (tests/port_names_test.sh:28-40), events' awk (tests/events_test.sh:190) and skill_test's copy of is_command (tests/skill_test.sh:25-26). A port that moves an arm out of dispatch would drop its command from all four. Put one reader in a new helper, tests/swarm_commands.sh, named only by these four: a test takes the reach of every helper it names (tests/port_tests_list_test.sh:15-16,268-272), and every test names tests/test_helpers.sh, so a reader there would give every test text reach (codex, critic). swarm_commands <repo> prints dispatch's arms, the early case's names (version, update) and every file under bin/ported/ (a missing dir is none). All four use it, which fixes the shared cause once (rules.md). The reader fails, naming what it found empty, when dispatch's arms and the markers give no name, even with version and update in the early case; and when the early case gives none. doc_check also fails when it finds no CONFIG_KEYS key. Stop skill_test extracting is_command, so marker-dispatch's change to is_command cannot reach it. In events_test, both 'read-only X is a command' and the loop over arms read swarm_commands. A marker routes nothing until marker-dispatch, so this PR proves only the name check; marker-dispatch proves the loop on a marked command (critic). config_test is left as it is (go-checks-owners). tests.tsv's rows for these four already mark text reach.

`version` and `update` exit at bin/swarm.sh:159-162 before event logging starts, so the events_test.sh loop at :195-206 that expects one event per command must leave them out (like RO_EXPECTED), or the migration adds two failures (codex).

**Done when:**
- On the tree as it is, all four tests pass and find the same commands as before; port_names still finds all 68 command rows of docs/port/names.tsv.
- tests/port_tests_list_test.sh passes with no row added or changed for any test other than these four.
- Proof in the PR, on a no-.git copy: the policy arm deleted from dispatch and bin/ported/policy added. doc_check, skill_test and port_names each still find every command and pass, and events_test's 'read-only policy is a command' check passes.
- Proof in the PR, on a no-.git copy: dispatch's arms deleted, no markers, the early case intact. Each of the four fails with a line saying it found no command in dispatch or the markers. With the early case deleted and dispatch intact, each fails saying the early case gave none. With CONFIG_KEYS emptied, doc_check fails saying it found no settings.
- Mutation: make swarm_commands skip bin/ported/ and the first proof goes red.
- scripts/select-tests.sh --run passes
- tests/events_test.sh's per-command event loop skips version and update and passes

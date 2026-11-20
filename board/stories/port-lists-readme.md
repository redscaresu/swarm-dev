---
kind: docs
status: blocked
epic: port-inventory
depends_on: [port-tests-list, port-sites-list, port-swarm-names, port-locks, port-frozen-names, port-frozen-fields, port-exit-codes, go-module-build]
needs: port-tests-list (docs/port/tests.tsv and tests/port_tests_list_test.sh); port-sites-list (docs/port/sites.tsv and tests/port_sites_test.sh); port-swarm-names (docs/port/swarm-names.tsv and tests/port_swarm_names_test.sh); port-locks (docs/port/locks.tsv and tests/port_locks_test.sh); port-frozen-names (docs/port/names.tsv and tests/port_names_test.sh); port-frozen-fields (docs/port/fields.tsv and tests/port_fields_test.sh); port-exit-codes (docs/port/exit-codes.tsv); go-module-build (AGENTS.md's tree lines for go.mod, cmd/swarm/ and scripts/build.sh (go-module, .swarm/go-module/lead.json))
touches: [docs/port/README.md, AGENTS.md:tree block (Working on this repository), AGENTS.md:development rules list, llms.txt:docs map]
estimate_lines: 120
---

# docs/port/README.md says what each list holds, how a port and its reviewer use it, and the closed plumbing list; AGENTS.md and llms.txt point at it

Uses docs/port/tests.tsv (port-tests-list), sites.tsv (port-sites-list), swarm-names.tsv (port-swarm-names), locks.tsv (port-locks), names.tsv (port-frozen-names), fields.tsv (port-frozen-fields) and exit-codes.tsv (port-exit-codes), and the test each list story adds. Also uses AGENTS.md's tree as go-module-build leaves it (go-module).
- Before you edit: AGENTS.md's tree at your base must list cmd/swarm/ (go-module-build). If it does not, stop and tell the conductor: a depends_on slug with no story file counts as finished (bin/lib/board.sh:2819-2826), so the edge may not have held.
- Write docs/port/README.md. For each file: what it lists, the rule its test applies, and what a PR must do. A PR adds a row for a new SWARM_ name, lock take site, inline site or inside-reaching test, and deletes a row where the reviewer sees it when a name goes. tests.tsv, names.tsv and fields.tsv rows stay as the record. Say that each test's failure line names the file and the row. Say how a reviewer reads a port against them (HLD:262, P6), and that a port epic's plan reads the tests.tsv rows whose go_check names it.
- The SWARM_ set is open at runtime: every SWARM_* variable reaches an agent (bin/lib/agents.sh:430-502). Say that swarm-names.tsv lists only the names the code mentions.
- The closed plumbing list (contradiction 15): die, within, scaled, nap and json keep a bash copy beside their Go counterpart until their last bash caller goes, and nothing else may. Give each one's call sites at the base, with the population and the command. The survey found 112 call sites of within with an argument across bin/swarm.sh, bin/lib/*.sh and hooks/*.sh, not the epic's 155.
- AGENTS.md: change the tree's `docs/ holds user docs only` line (AGENTS.md:180) to name docs/port/ as the one contributor folder under docs/. Add one item to the development rules pointing at docs/port/README.md. llms.txt: one link to docs/port/README.md.
- One item per line and one sentence per line (AGENTS.md's docs rule). Humanizer over the README, the AGENTS.md lines and the PR body.

**Done when:**
- docs/port/README.md names each of the seven files and its test by a path that exists. tests/llms_test.sh and tests/doc_check_test.sh pass with the new links. Each plumbing count carries its population and the command that gives it. AGENTS.md's tree keeps go-module-build's lines.
- scripts/select-tests.sh --run passes

---
kind: code
status: blocked
epic: release-client
depends_on: [plugin-id, fetch-quarantine]
needs: plugin-id: PLUGIN read from the install path, tests/update_test.sh with its copies and claude stub, and exit-codes.tsv's update row. fetch-quarantine (#1135): its macOS SUBSET line and its docs/running.md § First run edit, which this edits next.
touches: [bin/swarm.sh:update_plugin (and its bound constant above it), tests/update_test.sh:update-wrapper cases (after plugin-id's), .github/workflows/macos.yml:SUBSET, docs/running.md:First run (:158), docs/running.md:Offline (:206-207), docs/running.md:Updating, README.md:Updating, docs/port/exit-codes.tsv:update row (:163, when), docs/port/swarm-names.tsv:SWARM_UPDATE_WAIT row (new)]
estimate_lines: 180
---

# swarm.sh update ends by running the installed version's swarm.sh version once, within a time bound, so its binary is there before the next session

Needs plugin-id: PLUGIN read from the install path, tests/update_test.sh with its copies and claude stub, and the update row of docs/port/exit-codes.tsv. Needs fetch-quarantine (binary-fetch, PR #1135): its line of macOS's SUBSET (.github/workflows/macos.yml:33) and its edit of docs/running.md § First run, both of which this edits next.
Not a carve-out story: it changes update_plugin only, never release_upgrade or release_confirmed.
Where: update_plugin (bin/swarm.sh:225-229) runs the two claude commands, then prints the restart line. It never runs the new version.
Change: after `claude plugin update ${PLUGIN}`, find the copy Claude Code loads next. That is the installPath of the one entry with scope `user` under plugins["${PLUGIN}"] in ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json. The file's top-level keys are version and plugins. Each entry has scope, installPath, version, installedAt, lastUpdated and gitCommitSha (the lead's machine).
Match the ID exactly. Never pick the newest version folder: after prerelease is rolled back, the update installs the older version, and the older one must run (Done when (5)).
Then run `bash <installPath>/bin/swarm.sh version` once, with the session's environment, bounded by binary_within (bin/lib/binary.sh:91; merge.sh's within is not sourced yet at :239). The bound is a named constant beside update_plugin, 300 s, with a SWARM_UPDATE_WAIT seam for the tests; add its row to docs/port/swarm-names.tsv. The new copy's version can build Go from source, which takes minutes, so the bound is generous. Its output shows. Then print the restart line, as today.
When there is no such entry, more than one, no bin/swarm.sh at installPath, or the run passes the bound: print one line. It says the new version's binary was not fetched, and that `swarm.sh version` after the restart fetches it. update still exits 0.
The read may use python3: update is not in tests/speed_list.txt or tests/nopy_list.txt. An inline python3 that imports no bin/lib helper needs no docs/port/sites.tsv row (docs/port/README.md).
The running copy's update still fetches nothing for itself (binary_ensure runs after the early case, :244). Keep it that way.
Tests, in tests/update_test.sh after plugin-id's cases. A claude stub whose `plugin update` writes installed_plugins.json naming a second copy, whose bin/swarm.sh is a stub that logs `$0 $*` to the same log. Cases: the wrapper runs once, after the plugin update; installPath names an older version folder while a newer folder sits beside it; no entry; two user entries; no swarm.sh at installPath; a -pre copy reading plugins["swarm-dev@swarm-dev-pre"] while only swarm-dev@swarm-dev has an entry; a wrapper stub that sleeps past SWARM_UPDATE_WAIT=2.
Add tests/update_test.sh to macOS's SUBSET (.github/workflows/macos.yml:33), with its line in the comment above it, so the path parse and this read run under bash 3.2.
Docs, same PR:
- docs/running.md § Updating (:209-227) and README.md § Updating (:124-131): `swarm.sh update` now also runs the new version's `swarm.sh version` once, within 5 minutes. The separate 'Then run swarm.sh version' step (:225) is needed only after a plain `claude plugin update`. Name the -pre pair beside the stable command.
- docs/running.md § First run (:158): update does not fetch the running copy's binary, but it does run the newly installed copy's `swarm.sh version`, which fetches that copy's.
- docs/running.md § Offline (:206-207): the same for update.
- docs/port/exit-codes.tsv:163, the update row's when column: the plugin update ran, then the new version's swarm.sh version, or a line saying why not.
Run the humanizer.
Mutations, on a worktree copy: drop the wrapper run (the runs-once case goes red); pick the highest version folder instead of installPath (the older-version case goes red); drop the bound (the sleeping-stub case goes red by timeout).

**Done when:**
- With the stub's update writing installed_plugins.json, `swarm.sh update` runs <installPath>/bin/swarm.sh version exactly once, after `claude plugin update` (one log, in order). Its line is in update's stdout before the restart line.
- With installPath naming an older version folder and a newer folder beside it, the older folder's swarm.sh runs and the newer one's does not.
- With no user entry for the ID, two user entries, or no bin/swarm.sh at installPath: exactly one line naming `swarm.sh version`, exit 0, and no wrapper run.
- From a -pre copy, an entry for swarm-dev@swarm-dev alone counts as no entry.
- With a wrapper stub that sleeps and SWARM_UPDATE_WAIT=2, update returns within 10 s, exits 0, and prints the one line naming `swarm.sh version`.
- macos-tests is green on the PR's head and its log shows tests/update_test.sh ran.
- Each mutation turns its named case red on a worktree copy. The PR quotes the FAIL lines.
- docs/running.md § Updating, § First run and § Offline, README.md § Updating and the update row of docs/port/exit-codes.tsv say update runs the new version's swarm.sh version once, within its bound. docs/port/swarm-names.tsv has the SWARM_UPDATE_WAIT row. tests/doc_check_test.sh passes. The PR says the humanizer ran.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

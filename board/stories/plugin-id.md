---
kind: code
status: ready
epic: release-client
depends_on: []
touches: [bin/swarm.sh:PLUGIN and MARKETPLACE (the plugin ID lines, :128-129), tests/update_test.sh (new), tests/merge_rules_test.sh:-pre release_upgrade block (new, after :413), docs/reference-merging.md:Releases (the plugin update sentence, :1182-1183), docs/port/exit-codes.tsv:update row (:163, pinned by)]
estimate_lines: 170
risk: high
---

# swarm.sh update and merge --release's plugin update act on the plugin ID the copy is installed as

Needs no other story.
Carve-out story (HLD:486-490, P12). It changes which plugin release_upgrade updates and where it looks for the new version (bin/lib/merge.sh:2704, :2710-2711), in bash, and its parse runs on every swarm.sh call. The user gave their go for it on 2026-11-22. The user merges it in a merge = human window: the lead sets merge = human, the user merges, the lead sets it back (the epic's Your part; this project runs merge = agent). Do not merge it.
Lines are at origin/main e9278e7b.
Where: bin/swarm.sh:128-129 sets PLUGIN=swarm-dev@swarm-dev and MARKETPLACE=swarm-dev as fixed text. update_plugin (:225-229) and release_upgrade (merge.sh:2700-2738) read them.
Change: read both from SWARM_HOME's path. When it is <dir>/plugins/cache/<marketplace>/<plugin>/<version>, MARKETPLACE=<marketplace> and PLUGIN=<plugin>@<marketplace>. Any other path (a git checkout, a test's tree) keeps swarm-dev@swarm-dev and swarm-dev.
This is Claude Code's real layout: on the lead's machine swarm-dev@swarm-dev sits at plugins/cache/swarm-dev/swarm-dev/0.31.3 (installed_plugins.json installPath).
Match whole path segments: the two segments above <marketplace> must be exactly `plugins` then `cache`. No prefix or substring match.
Bash builtins only (parameter expansion), valid in bash 3.2: every swarm.sh call pays for it, and the speed job counts process starts.
Keep PLUGIN and MARKETPLACE as the globals they are. merge.sh's code needs no edit. Fix release_upgrade's header comment (:2688-2699) only if it names the fixed ID.
No new SWARM_ or SWARMDEV_ name, no setting. swarm.sh upgrade is out of scope: it names no plugin (the epic).
Tests drive swarm.sh from outside, so they survive port-release:
- New tests/update_test.sh. Run `swarm.sh update` from no-.git copies of the tree (as tests/binary_version_test.sh:59-63's copy() makes them) at <tmp>/claude-config/plugins/cache/swarm-dev-pre/swarm-dev/1.0.0, at .../cache/swarm-dev/swarm-dev/1.0.0, at a path whose segment above the marketplace is not `cache`, and from the checkout. Put a claude stub that logs its args first on PATH, and set SWARMDEV_BIN so no copy fetches. update-runs-new-wrapper adds its cases to this file next.
- tests/merge_rules_test.sh: one block after the no-terminal cases (after :413). It runs the same own_release with SWARM (tests/merge_fixture.sh:15) pointed at a copy under ${CLAUDE_CONFIG_DIR}/plugins/cache/swarm-dev-pre/swarm-dev/1.2.0, with the new version's stub swarm.sh at .../swarm-dev-pre/swarm-dev/1.3.0/bin/swarm.sh. Leave own_release (:378-381) to release-done.
bash 3.2: tests/update_test.sh joins macOS's SUBSET in update-runs-new-wrapper, once fetch-quarantine (#1135) has merged its own SUBSET line (it owns .github/workflows/macos.yml:SUBSET). Until then, check it here by hand once: with the claude stub first on PATH and CLAUDE_CONFIG_DIR a temp folder (never the real claude or ~/.claude), and SWARM_PROJECT unset, run `/bin/bash <the -pre copy>/bin/swarm.sh update` and quote `/bin/bash --version`'s first line and the stub's log in the PR.
Docs, same PR:
- docs/reference-merging.md § Releases, the sentence that names `claude plugin marketplace update swarm-dev` and `claude plugin update swarm-dev@swarm-dev` (:1182-1183). It names the installed plugin's marketplace and ID instead, with the stable and the -pre pair as examples. Leave the wait sentence (:1181-1182) to release-done.
- docs/port/exit-codes.tsv:163, the `update 0` row: its pinned-by column becomes tests/update_test.sh in place of none.
Run the humanizer over the changed prose.
Mutations, on a worktree copy: put PLUGIN back to fixed text (the -pre cases go red); accept any segment above the marketplace (the not-cache case goes red).

**Done when:**
- From the copy at plugins/cache/swarm-dev-pre/swarm-dev/1.0.0, `swarm.sh update` runs exactly `claude plugin marketplace update swarm-dev-pre`, then `claude plugin update swarm-dev@swarm-dev-pre` (the stub's log, in that order).
- From the copy at plugins/cache/swarm-dev/swarm-dev/1.0.0, from the not-cache path and from the checkout, it runs `plugin marketplace update swarm-dev`, then `plugin update swarm-dev@swarm-dev`, as today.
- merge --release --upgrade run from the -pre copy logs `plugin marketplace update swarm-dev-pre|plugin update swarm-dev@swarm-dev-pre`. It starts cache/swarm-dev-pre/swarm-dev/1.3.0/bin/swarm.sh upgrade once in each project with agents, and prints the restart line.
- Every existing release_upgrade case in tests/merge_rules_test.sh passes unchanged.
- The PR quotes the by-hand /bin/bash 3.2 run: its version line and the stub's log naming swarm-dev-pre.
- The speed job is green on the PR's head.
- Each mutation turns its named case red on a worktree copy. The PR quotes the FAIL lines.
- docs/reference-merging.md names the installed plugin's ID in place of the fixed one, and docs/port/exit-codes.tsv's update row names tests/update_test.sh. tests/doc_check_test.sh passes. The PR says the humanizer ran.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

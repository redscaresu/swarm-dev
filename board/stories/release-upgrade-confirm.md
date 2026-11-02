---
kind: code
status: ready
epic: merge-mechanics
depends_on: []
touches: [bin/lib/merge.sh:release_upgrade, bin/lib/merge.sh:merge_pr options, commands/swarm.md:release arm, docs/reference-merging.md:§ Releases, docs/reference-merging.md:§ Commands, docs/running.md:Updating, tests/merge_rules_test.sh:release_upgrade cases, AGENTS.md:merge usage line, skills/swarm-dev/SKILL.md:merge --release line]
estimate_lines: 180
easy: false
---

# merge --release asks before moving agents, and with no terminal moves none and says so (#694)

#694, the confirm (HLD:462; epic Constraints). release_upgrade (bin/lib/merge.sh:2303-2332, called at 1232 for --release only) runs the new version's `swarm.sh upgrade` in every agent project with no confirm. Keep the plugin update and the restart line; gate only the upgrade loop. With `--upgrade` on merge --release it runs as today. Without it, on a terminal (stdin a tty) it asks `Move the running agents onto v<new> now? [y/N]` and runs only on y. With no terminal it runs none and prints `upgrade not run: no terminal to confirm it` with what to run (merge --release --upgrade next time, or the per-project command, as the warnings at 2324-2330 name it). The lead runs merge --release in the background (commands/swarm.md:655), where there is no tty, so the release arm asks the user before the merge and passes --upgrade on yes. merge_pr's option loop (merge.sh:1015-1020) takes --upgrade only with --release, and its usage line names it. The guard (hooks/merge-guard.sh check_cmd) allows any flags on a lone swarm.sh merge: no hook change. AGENTS.md states nothing about the upgrade, and retro-gate edits its release lines: leave it. tests/merge_rules_test.sh:244-277 covers release_upgrade today; those cases add --upgrade. The new --upgrade flag also goes in AGENTS.md's `merge [--board|--release]` usage line and in skills/swarm-dev/SKILL.md where it names merge --release (keep tests/skill_test.sh's 60-line cap).

**Done when:**
- tests/merge_rules_test.sh: merge --release --upgrade of the plugin's repo runs the stub upgrade once per project (the existing cases, with the flag).
- tests/merge_rules_test.sh: merge --release without --upgrade, stdin from /dev/null, runs no upgrade, prints the `upgrade not run:` line, still updates the plugin and still prints the restart line.
- tests/merge_rules_test.sh: without --upgrade on a terminal (python3 -I with the pty module), answering n runs no upgrade and answering y runs it.
- tests/merge_rules_test.sh: --upgrade without --release fails with the usage line.
- commands/swarm.md's release arm asks the user before the merge and passes --upgrade on yes; docs/reference-merging.md § Releases and § Commands and docs/running.md § Updating say merge --release asks.
- The PR body shows the no-terminal and answer-n cases red with the gate removed.
- On a terminal, a blank answer, EOF and an unrecognised answer each run no upgrade ([y/N] defaults to no).

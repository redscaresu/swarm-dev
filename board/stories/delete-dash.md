---
kind: code
status: ready
depends_on: []
touches: [bin/swarm.sh:dash dispatch arm and usage line, bin/lib/dash.sh, bin/lib/dash_render.py, bin/lib/dash_slow.py, bin/lib/dash_age.py, bin/lib/dash_finished.py, bin/lib/dash_installed.py, bin/lib/dash_legend.py, scripts/demo-dash.sh, docs/dash.md, tests/:dash test files, scripts/test-map.tsv:dash rows, Makefile:SHELLCHECK dash entries, .github/workflows/ci.yml:shellcheck dash entries, README.md:dash lines, AGENTS.md:dash command bullets, docs/:dash mentions, commands/:dash mentions, skills/swarm-dev/:dash mentions, docs/port/:dash rows]
estimate_lines: 300
---

# Delete `swarm.sh dash`, the terminal dashboard, and its tests

The user decided on 2026-11-20 that the Go rewrite does not port the TUI: `swarm.sh dash` is deleted in bash now, in stage 1, instead of being ported in stage 2. v0.32.0 is a minor release, so a removed command is allowed there. `status` stays and is unchanged.

Delete the command and everything only it uses:
- the `dash` dispatch arm and its usage line in bin/swarm.sh, with its `--watch`, `--project` and `--check` forms;
- bin/lib/dash.sh and the six helpers bin/lib/dash_render.py, dash_slow.py, dash_age.py, dash_finished.py, dash_installed.py and dash_legend.py;
- scripts/demo-dash.sh and docs/dash.md;
- every tests/*_test.sh that exists only to test dash (about 18 files; list each in the PR), and their rows in scripts/test-map.tsv, the Makefile's and CI's shellcheck lists, and docs/port/ (tests.tsv, sites, names and the other inventory lists: a row for a deleted file or name goes, and the frozen-names list drops `dash` with the date and the user's decision).

Keep everything another command still uses. Read each function and helper before you delete it: next's `_step --dash` path, dash_no_agent, the lead queue, panes.py, stall.py, stall_py.py and the run-times rows that status and next write are shared, and stay, unless nothing but dash calls them. Where a shared function has a dash-only branch, remove just that branch. Say in the PR which shared pieces you kept and why.

Docs move in the same PR: every line in README.md, AGENTS.md, docs/, commands/ and skills/swarm-dev/ that names `swarm.sh dash` is removed or reworded, and tests/doc_check_test.sh passes. AGENTS.md's "Useful while it runs" list loses its dash bullets.

This PR changes .github/workflows/ci.yml and the Makefile (protected), so the user merges it.

**Done when:**
- `swarm.sh dash` prints the usage text for an unknown command and exits 2, and `swarm.sh` usage no longer lists it
- No file under bin/, hooks/, scripts/, tests/ or docs/ names `dash.sh`, `dash_render`, `dash_slow`, `dash_age`, `dash_finished`, `dash_installed`, `dash_legend` or `demo-dash` (shown with one grep in the PR), and no doc names `swarm.sh dash`
- `swarm.sh status` and `swarm.sh next` give the same output as before on their test fixtures
- tests/doc_check_test.sh, tests/skill_test.sh, tests/command_names_test.sh and the port inventory tests (tests/port_*_test.sh) pass
- scripts/select-tests.sh --run passes, and CI's full run is green

---
kind: code
status: ready
epic: port-inventory
depends_on: []
touches: [docs/port/names.tsv, tests/port_names_test.sh]
estimate_lines: 230
---

# docs/port/names.tsv freezes v0.31.3's commands, settings, removed settings and hook paths, and a test fails when one is gone

Needs no other story.
- Write docs/port/names.tsv (`#` header: kind, name, where), drawn at tag v0.31.3:
  - command: every arm of bin/swarm.sh's dispatch and its early case (at 7b480edf, 66 arms, 18 of them internal `_` arms, plus update and version);
  - setting: every key in CONFIG_KEYS (bin/swarm.sh:262);
  - removed-setting: each key in REMOVED_KEYS (bin/swarm.sh:265), which loads with a warning, and lessons_file (:283), which loads silently;
  - hook: each event and command in hooks/hooks.json, and bin/gh-shim/gh.
- Check that v0.31.2 has the same names (`git diff v0.31.2 v0.31.3 -- bin/swarm.sh hooks/hooks.json`), and say so in the header. Flags are not in the list: dropped-lines' --story came in v0.31.3.
- Add tests/port_names_test.sh. It reads names.tsv and fails, naming each name that is gone:
  - command: still an arm, parsed as doc_check does (tests/doc_check_test.sh:30-34). When binary-wrapper moves a ported command's arm out (contradiction 15), this test must read its marker too; the header says so;
  - setting: `swarm.sh config` in a stand-in project of the test's own, as tests/config_test.sh does, prints a `<key> = ` line for it (show_config, bin/swarm.sh:373-391). That is checked from outside, so it survives config's port;
  - removed-setting: a stand-in config that sets the key still loads (`swarm.sh config` exits 0), and for a REMOVED_KEYS key stderr names it in a warning;
  - hook: hooks/hooks.json still runs that command on that event, and the script exists.
- Each failure line names docs/port/names.tsv and the name. Source tests/test_helpers.sh first. List files with find (skip __pycache__, *.pyc), not git, so the test runs the same on a copy of the worktree without .git.
- Prove it red on a copy without .git: an arm removed, a CONFIG_KEYS key removed, a REMOVED_KEYS key removed, the lessons_file skip removed, a hooks.json entry removed.
- Humanizer over the header lines and the PR body.

bin/gh-shim/gh is in the hook population but is not registered under any event in hooks/hooks.json: swarm.sh puts it on PATH. Give the shim row its own check, that its executable path exists, and require a hooks.json registration only for the event-bound hooks (codex).

**Done when:**
- names.tsv has a row for every arm, setting, removed setting and hook path of v0.31.3. tests/port_names_test.sh passes and goes red on each of the five seeded cases on a copy without .git.
- scripts/select-tests.sh --run passes

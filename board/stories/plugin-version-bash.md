---
kind: code
status: ready
epic: binary-wrapper
depends_on: []
touches: [bin/swarm.sh:plugin_version, tests/config_test.sh:version cases, tests/events_test.sh:evv]
estimate_lines: 95
---

# plugin_version reads plugin.json without python3

Needs no other story. plugin_version (bin/swarm.sh:133) runs python3 json.load on stdin. Six callers pipe into it, one a git show of origin's plugin.json (bin/swarm.sh:136; bin/lib/agents.sh:945,987; bin/lib/board.sh:1421; bin/lib/lifecycle.sh:5360; bin/lib/dash.sh:774). Rewrite it in bash builtins only: no python3, sed or awk, since each start counts in the speed job. Keep the stdin interface. It prints the top-level "version" string for every input python3's json.load accepts, nested objects included, by tracking depth and strings (escaped quotes too). It exits 1 with empty stdout only when the top-level object has no version, the value is not a string, the input is empty, or the top-level object never closes (codex). It never takes a version from a nested object (rules.md: exact records). plugin.json is 470 bytes, so a character scan costs little, and dash (bin/lib/dash.sh:774) loses a python3 start. tests/events_test.sh:355 evals the one line that `grep '^plugin_version()'` finds: the scanner is more than one line, so fix that extraction. show_version's python3 compare (bin/swarm.sh:142) stays; release-client rewrites show_version. `version` and `update` still run before any project lookup (bin/swarm.sh:159-162).

**Done when:**
- In tests/config_test.sh's version cases (:425), with python3 on PATH replaced by a stub that logs and exits 1, and SWARM_LATEST_URL unreachable, swarm.sh version prints 'swarm-dev <the version in .claude-plugin/plugin.json>' and the stub logs no call.
- plugin_version prints python3's value and exits 0 on each fixture: pretty-printed, minified, version not the first key, a nested object with its own version key before the top-level one, another after it, and a string value holding braces, a colon and an escaped quote before the version.
- It exits 1 with empty stdout on: no top-level version (only a nested one), a numeric version, empty input, and a file cut off before its top-level object closes.
- tests/events_test.sh passes, and the speed job is green on the PR.
- Mutation: make it return the first "version" it meets and the nested-before case goes red; drop the depth check and the only-nested case goes red.
- scripts/select-tests.sh --run passes

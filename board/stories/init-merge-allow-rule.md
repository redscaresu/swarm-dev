---
kind: code
status: ready
epic: merge-agent-setup
depends_on: []
touches: [bin/lib/lifecycle.sh:init_claude (new), bin/lib/lifecycle.sh:merge_allowed (new), bin/lib/lifecycle.sh:init_project, tests/init_test.sh:merge allow rule cases, docs/reference.md:init Claude Code checks, README.md:Getting started init step]
estimate_lines: 130
easy: false
risk: high
---

# init checks for the swarm.sh merge allow rule and names the user's step

init_project (bin/lib/lifecycle.sh:1932-1966) checks nothing in Claude Code's settings. Add merge_allowed (new): true when a permissions.allow rule allows the `swarm.sh merge` command in the user's settings (CLAUDE_CONFIG_DIR or ~/.claude settings.json) or the project's .claude/settings.json or .claude/settings.local.json. It reads only permissions.allow (python3 -I, json), prints nothing else from those files (they may hold tokens under env), and never writes a settings file or ~/.claude.json. Add init_claude (new), called by init_project before its last line: when merge_allowed is false, print the user's step, the exact rule and the file, and that under merge = agent conductors are refused every merge without it (v0.28.0: the user merged 8 approved PRs by hand). Document it in docs/reference.md and README.md's Getting started.

**Done when:**
- tests/init_test.sh gains cases with a stub CLAUDE_CONFIG_DIR: rule present (no step), absent (the step names the rule and file), present only in .claude/settings.local.json (no step), and a settings file whose env token never appears in init's output. Each fails with merge_allowed returning a constant.
- The test compares each settings file's checksum before and after init: none changes.

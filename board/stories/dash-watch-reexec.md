---
kind: code
status: ready
epic: dash-tells-the-truth
depends_on: []
touches: [bin/swarm.sh:dash_watch, tests/dash_reexec_test.sh (new), docs/dash.md (--watch paragraph)]
---

# dash --watch re-execs itself when the installed plugin version changes

The installed plugin is a versioned dir (`~/.claude/plugins/cache/swarm-dev/swarm-dev/<version>/`, recorded in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json` under `swarm-dev@swarm-dev` with installPath and version), so SWARM_HOME's own plugin.json never changes; installed_plugins.json is the version file. At dash_watch entry (bin/swarm.sh:2808) read that entry with python3, as plugin_version does (:66). Re-exec only when SWARM_HOME is that installPath, so a dev checkout never jumps to the installed copy. At the top of the loop (:2816, before dash_size) re-read it; when the version differs and `<new installPath>/bin/swarm.sh` is an executable regular file, `exec` it with `dash --watch <every>` plus `--ladder`/`--tree` for the toggles as they stand now. exec keeps the PID and skips the EXIT trap; the new process re-enters the alternate screen itself. An unreadable or missing file means no re-exec and the loop carries on. Test in a new file so it does not clash with other dash_test.sh hunks.

**Done when:**
- tests/dash_reexec_test.sh (new): CLAUDE_CONFIG_DIR is a temp dir; bin/ and .claude-plugin/ are copied to $T/0.1.0 and $T/0.2.0, and 0.2.0's swarm.sh is edited so its frame carries a marker; installed_plugins.json names 0.1.0. `$T/0.1.0/bin/swarm.sh dash --watch 1 --tree` runs non-tty in the background. Within 3 s the marker is absent. After rewriting installed_plugins.json to 0.2.0, the marker appears within 10 s, the frame still shows the tree, and the background PID is unchanged. Run from a copy that is not the installPath, the same swap never shows the marker. The PR shows the swap check failing with the re-exec removed. The epic's checks before every stage pass.

**From review (binding; overrides the scope above where they differ):**
- installed_plugins.json is {version, plugins: {"swarm-dev@swarm-dev": [{scope, installPath, version, ...}]}}, a list of per-scope entries. At dash_watch entry take the entry whose installPath (resolved with pwd -P) equals SWARM_HOME (also resolved with pwd -P) and remember its scope; each frame re-read that scope's entry and re-exec <installPath>/bin/swarm.sh when its version differs and that file is executable.
- Done when uses the real shape, plus a second entry with another scope whose change must not trigger. The test runs in a temp git project with board/stories/README.md and .claude/swarm/config and stub herdr and gh on PATH, as tests/dash_test.sh does, so it still passes after dash-no-board merges. A copy that is not the installPath shows no re-exec marker for 10 s after the swap.

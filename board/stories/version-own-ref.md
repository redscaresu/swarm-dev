---
kind: code
status: blocked
epic: release-client
depends_on: [plugin-id]
needs: plugin-id: MARKETPLACE read from the install path, set just above LATEST_URL's new place.
touches: [bin/swarm.sh:LATEST_URL (and its comment, :125-127), tests/version_ref_test.sh (new), commands/swarm.md:version step (:46-47)]
estimate_lines: 80
easy: true
---

# swarm.sh version warns only about a newer version on the ref its marketplace follows

Needs plugin-id: MARKETPLACE read from the install path, set just above where LATEST_URL now goes.
Not a carve-out story.
Where: LATEST_URL (bin/swarm.sh:127) is main's plugin.json. Main runs ahead of both refs, since main's marketplace.json names ref stable (#1118). So a stable machine is warned about a version it cannot get.
Change: make the default https://raw.githubusercontent.com/redscaresu/swarm-dev/<ref>/.claude-plugin/plugin.json. <ref> is `prerelease` when MARKETPLACE is exactly swarm-dev-pre, and `stable` otherwise, a checkout included. Set it after plugin-id's lines.
Both URLs answered on 2026-11-22 with version 0.31.3 (a curl by the planner).
SWARM_LATEST_URL still overrides it (a seam, docs/port/swarm-names.tsv:53). Builtins only: no new process.
show_version (:209-222) keeps its `curl --max-time 5`, its compare and its WARNING text. Change its body only if the URL must be built there.
Nothing here fixes an installed 0.31.2 or 0.31.3, which keeps reading main (the epic's Constraints).
Tests: new tests/version_ref_test.sh. SWARM_LATEST_URL is unset. A curl stub first on PATH logs its args and serves a plugin.json with a set version. Use no-.git copies at cache/swarm-dev-pre/swarm-dev/1.0.0 and cache/swarm-dev/swarm-dev/1.0.0, with SWARMDEV_BIN set so nothing fetches. tests/config_test.sh:425-429 and tests/timeouts_test.sh stay green.
Docs: no doc says what version compares against (the planner's grep). commands/swarm.md's version step (:46-47) gains one sentence: the WARNING names a newer version on the ref this install follows. Run the humanizer.
Mutation, on a worktree copy: map swarm-dev-pre to stable (the -pre URL case goes red).

**Done when:**
- From the -pre copy, `swarm.sh version` calls curl with --max-time 5 and https://raw.githubusercontent.com/redscaresu/swarm-dev/prerelease/.claude-plugin/plugin.json. From the stable copy and from the checkout, the URL ends /stable/.claude-plugin/plugin.json.
- The stub serving 99.0.0 gives the WARNING and `  swarm.sh update` lines. Serving the installed version gives no WARNING.
- With SWARM_LATEST_URL set, the stub logs that URL and no other.
- tests/config_test.sh and tests/timeouts_test.sh pass.
- The mutation turns the -pre URL case red on a worktree copy. The PR quotes the FAIL line.
- The PR quotes one real read of each default URL returning a version, run once.
- commands/swarm.md's version step names the ref. The PR says the humanizer ran.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

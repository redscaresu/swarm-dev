---
kind: code
status: blocked
epic: binary-fetch
depends_on: [fetch-ensure]
needs: fetch-ensure (binary_ensure, sourced above the version case and returning with one line on failure; tests/binary_fetch_stubs.sh; docs/running.md)
touches: [bin/swarm.sh:show_version, tests/binary_version_test.sh, docs/running.md:Updating]
estimate_lines: 80
easy: true
---

# swarm.sh version tries the fetch and says in one line when it could not

Needs fetch-ensure: binary_ensure, sourced above the version case and returning with one line on failure; tests/binary_fetch_stubs.sh; docs/running.md.
show_version (bin/swarm.sh:206-218) prints `swarm-dev <version>` first, then calls binary_ensure "${SWARM_HOME}". When that fails, its one line is printed and version goes on: it still exits 0, and the newer-version check still runs. update (:221-225) stays as it is: it needs no binary and makes no gh call (fetch-ensure checks that).
version runs before the gh-shim block (:288-292), on the caller's PATH. binary_fetch's binary_gh_path already skips every gh-shim folder.
In a git checkout binary_ensure does nothing, so tests/config_test.sh's version cases (:423-436) stay as they are.
Tests: new tests/binary_version_test.sh drives swarm.sh from outside and sources tests/binary_fetch_stubs.sh. go is a fail stub, and no case checks the exact gh call list, so each outcome holds whether or not fetch-fallback merges first.
release-client edits show_version after this (its Done when (2)-(3)).
Docs: docs/running.md's Updating says `swarm.sh version` after an update fetches the new version's binary, and says in one line when it could not. Run the humanizer.

**Done when:**
- An installed-copy fixture with no binary: `swarm.sh version` prints swarm-dev <version>, leaves an executable <copy>/swarm cmp-equal to the fake release, and exits 0.
- With the gh stub failing the download, go a fail stub and SWARM_LATEST_URL unreachable: the version line, then exactly one line saying the binary could not be fetched and why, then exit 0.
- With an older version's gh-shim folder (logging, exit 1) first on PATH, version's fetch leaves that log empty.
- tests/config_test.sh's version cases pass unchanged.
- Mutations on a copy, FAIL lines quoted, each turning a named case red: the binary_ensure call removed (the first case); the failure's line dropped (the second case); version made to exit on the failure (the second case's exit 0).
- docs/running.md's Updating says it. tests/doc_check_test.sh passes. The PR says the humanizer ran.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

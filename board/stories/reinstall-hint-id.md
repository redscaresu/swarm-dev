---
kind: code
status: blocked
epic: release-client
depends_on: [plugin-id, fetch-quarantine]
needs: plugin-id: PLUGIN set from the install path before bin/swarm.sh sources binary.sh (:128-129, then :234). fetch-quarantine (binary-fetch, PR #1135): it edits binary_download, whose fix line this changes.
touches: [bin/lib/binary.sh:BINARY_REINSTALL, bin/lib/binary.sh:binary_download (its fix line, :566), tests/binary_build_test.sh:-pre reinstall hint cases (new, beside :180)]
estimate_lines: 50
easy: true
---

# The binary's reinstall hint names the plugin ID the copy is installed as, on both of its paths

Needs plugin-id: PLUGIN set from the install path before bin/swarm.sh sources binary.sh (:128-129, then :234). Needs fetch-quarantine (binary-fetch's last story, PR #1135): it edits binary_download, whose fix line this changes.
Not a carve-out story. The epic's Out of scope gives the download code to binary-fetch, and this changes only the hint's text. The lead may drop it (contradictions).
Where: two sites spell swarm-dev@swarm-dev. BINARY_REINSTALL (bin/lib/binary.sh:290) is what binary_copy_lists (:471) prints when gh is too old to download, and binary_ensure's other stops. binary_download's local fix (:566) is what it prints when gh is fit. On a -pre machine both tell the user to reinstall the wrong plugin.
Change: build BINARY_REINSTALL from ${PLUGIN}, falling back to swarm-dev@swarm-dev when PLUGIN is unset (a test that sources binary.sh alone, under set -u). binary_download uses BINARY_REINSTALL instead of its own copy.
Tests: tests/binary_download_test.sh:35 and tests/binary_build_test.sh:180 pin the stable text, and stay. Add two cases to tests/binary_build_test.sh beside :180, each from a copy at cache/swarm-dev-pre/swarm-dev/<v> with scripts/build.sh missing: one with a gh stub new enough to download (binary_download's line), one with a gh stub older than BINARY_GH_MIN (binary_copy_lists's line). Each prints the hint with swarm-dev@swarm-dev-pre.
No doc names the ID in the hint: docs/running.md:184 says 'Reinstall swarm-dev'.
Mutations, on a worktree copy, each on its own: put the fixed ID back in BINARY_REINSTALL (the old-gh case goes red); give binary_download its own fixed text again (the fit-gh case goes red).

**Done when:**
- From the -pre copy with scripts/build.sh missing and a fit gh, the `binary:` line ends `claude plugin uninstall swarm-dev@swarm-dev-pre, then claude plugin install swarm-dev@swarm-dev-pre)`.
- The same with a gh older than BINARY_GH_MIN: binary_copy_lists's line ends the same way.
- tests/binary_download_test.sh and tests/binary_build_test.sh's stable cases pass unchanged.
- Each mutation turns its named case red on a worktree copy. The PR quotes the FAIL lines.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

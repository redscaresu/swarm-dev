---
kind: code
status: blocked
epic: binary-fetch
depends_on: [fetch-ensure, fetch-build, fetch-attest]
needs: fetch-ensure (binary_ensure, whose no-binary branch this changes; binary_gh_path; tests/binary_fetch_test.sh's call-sequence check; docs/running.md's Offline section); fetch-build (binary_build and its stop lines); fetch-attest (BINARY_GH_MIN)
touches: [bin/lib/binary.sh:binary_ensure (no-binary branch), bin/lib/binary.sh:header comment, tests/binary_fallback_test.sh, tests/binary_fetch_stubs.sh:gh stub version form, tests/binary_fetch_test.sh:call sequence check, README.md:Requirements, docs/running.md:Offline]
estimate_lines: 190
risk: high
---

# When the download cannot work here, an installed copy builds its binary from the source beside it and says so

Needs fetch-ensure: binary_ensure, whose no-binary branch this changes; binary_gh_path; tests/binary_fetch_test.sh's call-sequence check; docs/running.md's Offline section. Needs fetch-build: binary_build and its stop lines. Needs fetch-attest: BINARY_GH_MIN.
binary_ensure's no-binary branch (bin/lib/binary.sh):
- First, with PATH from binary_gh_path, `gh --version`. Read the version from its first line, `gh version X.Y.Z`, exactly. Older than BINARY_GH_MIN by a numeric compare of the dotted fields: this gh cannot verify, so build without downloading. A line it cannot read counts as too old, and the line says so; the build is the safe side, since nothing downloaded runs. No gh: skip this; binary_fetch returns BINARY_CANNOT for it.
- binary_fetch returning BINARY_CANNOT (no gh, a platform --list lacks, a failed download, a gh not logged in among them): binary_build. On success, one stderr line `binary: built from source, as <why the download could not work>`, export SWARMDEV_BIN, and the command runs. On binary_build's stop, one line naming both: why the download could not work, and binary_build's reason with what to do.
- Any other code stops as now, whether or not Go is installed: a wrong checksum, a failed attestation, a quarantine mark, a broken copy. Route on BINARY_CANNOT only, an allowlist.
The gh call contract becomes: gh --version, release download, attestation verify, and no other call. Add the --version form to tests/binary_fetch_stubs.sh's gh stub (it reports a version the test sets, by default BINARY_GH_MIN). Update tests/binary_fetch_test.sh's call-sequence check to the new contract.
gh not logged in: run the real gh once with an empty GH_CONFIG_DIR and GH_TOKEN, GH_ENTERPRISE_TOKEN and GITHUB_TOKEN unset, so no credential is read: `gh release download v0.31.3 --repo github.com/redscaresu/swarm-dev --pattern x --dir <empty tmp>`. Quote its exit code and stderr in the PR. The stub's not-logged-in case uses that text, so the case is checked against the thing itself.
Update bin/lib/binary.sh's header: an installed copy now builds too.
Docs: README.md's Requirements gains a Go row: optional, for the fallback, at go.mod's version. docs/running.md's Offline says it builds from source when Go is installed, and stops otherwise. It also says what a killed build leaves. Run the humanizer.
Tests: new tests/binary_fallback_test.sh drives swarm.sh from outside (no docs/port row) and sources tests/binary_fetch_stubs.sh. Use real go behind a logging stub, in a copy whose cmd/swarm/main.go prints a word (tests/binary_build_test.sh:42-64).
risk high: this routing decides whether a failed check is ever bypassed.

**Done when:**
- With real go behind a logging stub, five cases each exit 0, print the word, print exactly one stderr line saying it built from source and why, and leave an executable <copy>/swarm and no .fetch-* folder. The cases: the gh stub failing release download; it failing with the real not-logged-in text the PR quotes, whose line names gh auth login and not the network; a uname stub reporting Linux riscv64; the gh stub reporting a version below BINARY_GH_MIN, and then no release download is logged; no gh on PATH.
- The same five with go a fail stub, and again with no go on PATH: each exits 1 with one line naming why the download could not work and go.mod's Go version, with empty stdout and no <copy>/swarm. With bin/ported/config present, bash's config output is absent too.
- A wrong checksum and a failing attestation stub, with real go on PATH: fetch-ensure's one-line stop, and the go log is empty.
- A KILL to the call's process group while the go stub holds mid-build: no <copy>/swarm. The next call builds and exits 0.
- tests/binary_fetch_test.sh passes with the new call sequence. tests/binary_build_test.sh passes unchanged.
- Mutations on a worktree copy, FAIL lines quoted, each turning a named case red: the build branch removed (the five build cases); an attestation failure routed to the build (the attestation case); the gh version compare removed (the old-gh case); the route widened from BINARY_CANNOT to any failure (the checksum case).
- README.md's Requirements and docs/running.md's Offline say it. tests/doc_check_test.sh passes. The PR says the humanizer ran.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [ship-gates]
stage: v0.32.0
---

# The repo has one Go module that builds one binary, and CI holds it to the HLD's Go rules on Linux and macOS

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** `go build ./...` gives one binary from go.mod at the repo root, with the toolchain pinned and go.sum empty. One build script builds the four platform binaries and their checksum file, and a test checks the names it gives against the list it prints. CI fails a PR with unformatted Go, a `go vet`, `staticcheck` or `errcheck` finding, a line in go.sum or a failing Go test, each shown red once on a throwaway branch. A macOS job runs the Go tests and the chosen subset of the bash tests. `scripts/select-tests.sh` maps a changed Go file to tests instead of selecting every test, and tests/select_tests_test.sh fails a tracked Go file with no row. doc_check fails a doc that names a Go path that does not exist.

**Out of scope:**
- Any ported behaviour
- The wrapper, and `make test` building the binary (binary-wrapper)
- The import and clock checks (go-layers)
- Release builds (release-ci)
- Windows

**Constraints:**
- stage: v0.32.0.
- Standard library only. staticcheck and errcheck are installed in CI, pinned by version and hash (HLD:104-105,330-332); dependabot covers only github-actions, so those pins are kept by hand (.github/dependabot.yml).
- This epic owns the contract between the release and the wrapper: the asset name per platform, the checksum file's name and format, and the workflow path that signs the attestation (.github/workflows/release.yml). binary-fetch and release-ci read them from the build script, and neither writes a copy.
- Entry under cmd/, packages under internal/, and a build path that .gitignore names (HLD:179,229).
- New CI jobs run the board-only gate step from the base SHA as today's jobs do (.github/workflows/ci.yml:29-37), with SHA-pinned actions, persist-credentials: false and read-only permissions (zizmor).
- The 14-shard matrix and tests/test_shard_test.sh keep passing.
- No row of scripts/test-map.tsv matches cmd/, internal/ or go.mod today, so a Go PR selects every test until the map learns them (tests/select_tests_test.sh:1-15).
- doc_check's ROOTS has no cmd or internal (tests/doc_check_test.sh:36-37).
- Where it can, new CI work goes in its own job or workflow file, so parallel epics do not edit the same lines of ci.yml.

**Your part:**
- Lead: before the first story starts, install Go on this machine at the version the epic pins, check that a builder's pane runs `go build`, and name any GO* variable it needs in the board's agent_env. Agents get PATH and HOME but no GO* name (bin/lib/agents.sh:388).
- You merge every PR that changes .github/ or the root Makefile (protected paths).
- You add the Go checks and the macOS job to main's required checks once they have run green (HLD:504-505; ruleset 24181590).
- You look at the Actions bill after the first week of the new jobs (HLD:459-460).
- Carve-out (HLD:480-485): none expected. No story here touches the guard, merge or the release gates. A story would be listed only if it named env:, and the plan puts any GO* name in the board's agent_env instead.

**Areas:**
- go.mod
- cmd/
- internal/
- scripts/ (build script)
- .github/workflows/ci.yml
- .gitignore
- scripts/test-map.tsv
- scripts/select_tests.py
- tests/select_tests_test.sh
- tests/doc_check_test.sh
- AGENTS.md

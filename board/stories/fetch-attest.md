---
kind: code
status: ready
epic: binary-fetch
depends_on: []
touches: [bin/lib/binary.sh:binary_attest (new, after binary_find), bin/lib/binary.sh:BINARY_GH_MIN (new, beside binary_attest), tests/binary_attest_test.sh, docs/port/tests.tsv:tests/binary_attest_test.sh row]
estimate_lines: 100
risk: high
---

# binary_attest verifies a downloaded binary's build attestation against this repo's release workflow

Needs no other story.
Adds the attestation step only. Nothing calls it until fetch-ensure, so no doc changes; say so in the PR.
Where: bin/lib/binary.sh, a new block right after binary_find (:46), before binary_stale's comment.
binary_attest <file> <repo> <signer>: runs `gh attestation verify <file> --hostname github.com --repo <repo> --signer-workflow github.com/<repo>/<signer>`. The flag forms are gh 2.101.0's (`gh attestation verify --help`): --repo takes <owner>/<repo>, --signer-workflow takes [host/]<owner>/<repo>/<path>. gh comes from PATH. Any failure: one `binary: ` line saying the attestation did not verify and what to do, return 1, never a fallback. Print none of gh's output.
BINARY_GH_MIN, a named constant beside it: the oldest gh whose attestation verify takes --signer-workflow, from cli/cli's release notes, quoted with its link in the comment and the PR. fetch-ensure's README row names it; fetch-fallback compares the local gh with it.
Tests: new tests/binary_attest_test.sh sources binary.sh and adds its docs/port/tests.tsv row. Its own gh stub (fetch-download's stubs file is not merged yet) accepts only the exact arguments above, for a file whose basename is the asset name the test gives and whose bytes are cmp-equal to a fixture. Anything else logs and exits 1.
release-client runs it against a real release (its Done when (5)).
risk high: a check that passes while broken installs an unattested binary.

**Done when:**
- binary_attest <dir>/swarm-<os>-<arch> redscaresu/swarm-dev .github/workflows/release.yml returns 0. The stub logged exactly one call, with that file, --hostname github.com, --repo redscaresu/swarm-dev and --signer-workflow github.com/redscaresu/swarm-dev/.github/workflows/release.yml.
- With the stub failing: return 1, exactly one stderr line, none of the stub's output.
- BINARY_GH_MIN's comment and the PR quote the cli/cli release note that added --signer-workflow, with its link.
- Mutations on a copy, FAIL lines quoted, each turning a named case red: the --signer-workflow flag dropped (the first case); the file argument replaced by its folder (the first case); the failure path returning 0 (the failing case).
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

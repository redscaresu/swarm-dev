---
kind: code
status: ready
depends_on: []
touches: [bin/lib/binary.sh:binary_attest, tests/binary_attest_test.sh:release-commit cases]
estimate_lines: 120
fix: true
risk: high
---

# binary_attest refuses a signed binary from another release of the same repo

release-client's real-release check (board/epics/release-client.md § real-release-check results, 2026-11-23) uploaded v0.31.90's attested swarm-darwin-arm64 under v0.31.91's name on the throwaway copy, with SHA256SUMS rewritten to its sum. v0.31.91's wrapper installed it. binary_attest (bin/lib/binary.sh) runs `gh attestation verify` with only --repo and --signer-workflow. An attestation proves who built the file, not which release it belongs to. So anyone who can upload to a release can roll an install back to an older signed binary, with a known bug.

- Bind the attestation to the release being installed. Pass the release's commit to `gh attestation verify`, as `--source-digest <commit sha>` (or the matching flag of the gh the wrapper requires), with `--source-ref refs/tags/v<version>` or the ref release.yml signs from. Read the commit from the tag, through the same gh read the download uses.
- A binary attested at another commit stops the call with one line, naming the version and both commits, and runs nothing, as the other refusals do.
- Docs move with it, wherever docs/running.md and docs/reference*.md describe the attestation check.

**Done when:**
- A case in tests/binary_attest_test.sh: the gh stub's attestation for the asset names commit A, and the release's tag is at commit B. binary_attest refuses, with one line naming both commits, and no swarm is installed. With the attestation at B, it passes.
- The case goes red when the commit check is removed (proved on a copy of the worktree without .git).
- scripts/select-tests.sh --run passes

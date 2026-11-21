---
kind: lead
status: blocked
epic: release-ci
depends_on: [release-workflow, publish-plan-recover, build-check, release-refs, release-install-proof]
needs: release-workflow (release.yml on main); publish-plan-recover (scripts/publish-release.sh's existing-release states on main, which the reruns need); build-check (.github/workflows/build-check.yml on main); release-refs (the rulesets to copy, and swarm-dev's stable and prerelease, which must not move); release-install-proof (done with the copy, which this story reworks)
touches: [the throwaway copy]
estimate_lines: 0
easy: true
risk: high
---

# Lead: on the copy, prove the build check, the two-job publish, a failed verify, reruns after a failed publish, and the move under the rulesets

Uses main's release.yml, publish-release.sh (with publish-plan-recover's states) and build-check.yml, release-refs' rulesets, and the copy, which it reworks only once release-install-proof is done with it (codex, critic).
- Lead, first: the release.yml run on swarm-dev's push that merged release-workflow printed `none` with no gh call, and changed no release and no ref.
- Lead: push swarm-dev's main to the copy's main. Set the copy's prerelease at its v0.31.x tag. Recreate swarm-dev's three rulesets on the copy from `gh api`, and its release environment and move secret if release-ref-spike needed them.
- (1) On the copy, open a no-bump PR, a bump PR, and a bump PR with a Go file that fails only on linux/arm64. build-check: green with steps skipped, green and built, red naming linux/arm64.
- Each case below is its own bump commit to a new version (codex).
- (2a) A failed verify: bump with a copy-only build-job step that appends a byte to one binary after the checksum check. The publish job fails at verify, no attest, draft, attach, publish or move step runs, there is no draft, and prerelease does not move. Drop that step after.
- (2) Bump again. The build job had contents: read only. The publish job verified, attested, drafted, attached and published, then moved prerelease last. Download each asset with `gh release download`. Each passes `sha256sum -c SHA256SUMS` and `gh attestation verify <asset> --repo <copy> --signer-workflow <copy>/.github/workflows/release.yml`.
- (3) Add a temporary `update` rule on the copy's prerelease, then merge the next bump. The release is published, the move fails with the rule's message, and prerelease does not move. A push with no bump then prints `none` and is green. Lift the rule and 'Re-run all jobs': the plan prints only `move`, nothing is built, prerelease moves and no asset is replaced (same asset ids).
- (3b) For the next bump, cancel the publish job once the draft exists, then 'Re-run all jobs': all five files attached, published, moved.
- (6) The first move crossed a range that changes .github/workflows/, under the copied rulesets.
- Rollback: force-move the copy's prerelease back one version (allowed). A later push with no bump leaves it back.
- Time it from merge to ref move, against merge --release's 600 s wait (bin/lib/merge.sh:26). A fix, if needed, is release-client's.
- Keep the copy. At the end, check that swarm-dev's stable and prerelease are unchanged (L2).

**Done when:**
- This story's file records a run URL for each of (1), (2a), (2), (3), (3b), (6) and the rollback, each as stated. Each downloaded asset passes `sha256sum -c` and `gh attestation verify` with the copy's release.yml as the signer. The corrupted artifact left no draft and no move. The blocked move left prerelease where it was, and the no-bump push after it was green. Each 'Re-run all jobs' finished its release without replacing a published asset. The time from merge to ref move is recorded. swarm-dev's stable and prerelease name the same commits as at the start. Any step that fails stops the epic until the lead adds a fix story.

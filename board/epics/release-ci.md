---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [go-module]
stage: v0.32.0
---

# Goal 4, the publishing half

A release publishes four checked binaries and only then moves the prerelease ref. Every install follows the stable ref, and a rollback moves a ref back.

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** On a public throwaway copy of the repo: (1) The build check reports on every PR. It passes on a story PR that is no bump, builds the four binaries in a read-only job on a version-bump PR, and stays red when one platform fails to build. (2) After the merge the workflow builds again in a read-only job. A second job attaches the four binaries, their SHA-256 checksums and a build attestation, and only then moves the prerelease ref. Each of the four downloaded assets passes `sha256sum -c` and `gh attestation verify` with release.yml as the signer. (3) A failed publish leaves the ref where it was, and a rerun after a publish that failed once the release existed attaches the files and moves the ref. (4) A marketplace added the way users add it today installs what the stable ref holds and does not move when prerelease moves. (5) With prerelease moved back one version, an update and a restart bring back the older plugin.json and hooks; the binary half is proved by release-client's real-release check (release-client.md Done when (5)), as the user agreed on 2026-11-21. If Claude Code does not go back, docs/lead-by-hand.md has the rollback that does, before any port merges. (6) The workflow's push to prerelease works under the rulesets on stable and prerelease, and the pinned plugin validator passes main's marketplace.json. An install on that v0.31.x tag does not move when the marketplace.json PR merges.

**Out of scope:**
- swarm.sh's side: the plugin's ID, the version check, when a release counts as done (release-client)
- The wrapper's download and checks (binary-fetch)
- Moving the stable ref at a stage's end (the exit epics)
- A checksum file in git, or CI committing to main (HLD:213)
- One plugin per project (open question 4), beyond the lead's optional trial

**Constraints:**
- stage: v0.32.0.
- release.yml today is one job with contents: write, no checkout and no files (.github/workflows/release.yml:1-47). The build job stays read-only; only the publish job gains the attestation and contents permissions. Actions stay SHA-pinned and zizmor must pass.
- The release PR stays a version bump and nothing else. CI skips steps, not jobs, for exactly that PR (scripts/board-only.sh:41-61; .github/workflows/ci.yml:110-117), and the build check follows that pattern: a required check that never reports blocks every other PR, and wait-pr exits 2 on it.
- Today a rerun exits 0 once the tag exists (.github/workflows/release.yml:40-45). The publish job must finish a half-done release instead.
- The throwaway copy is public, as swarm-dev is: attestations work on a public repo.
- The stable branch exists at v0.31.2 before main's marketplace.json names it, or every install breaks. That change is a kind: lead story that depends on the branches story: no agent builds it and the user merges it, since nothing holds .claude-plugin/ before v0.32.0.
- The source form {source: url, url, ref} was tried on the lead's Claude Code, not on the validator CI pins, @anthropic-ai/claude-code@2.1.284 (.github/workflows/ci.yml:117). Prove it there first.
- A rollback moves a ref back, so the rulesets allow the lead a force-push. A bad port is reverted or fixed on main before the next release, since that release moves prerelease forward past the rollback.
- Stable moves only at a stage's end (HLD:196-198). There is no early exit: the exit epic is planned only once every other epic of its stage is built (HLD:352-353). So a fix reaches other machines at the stage's end, and docs/reference-merging.md says so.
- No patch can be cut in stage 1 (ship-gates), so nothing is released between the marketplace.json merge and v0.32.0.
- The ruleset on stable and prerelease cannot tell the lead from an agent: they share one gh login (bin/lib/agents.sh:388). The lead's ref checks in step L2 cover that (critic).

**Your part:**
- Lead: create the `stable` and `prerelease` branches at v0.31.2 (a kind: lead story; it pushes to the shared repo).
- Lead: create the `pre-marketplace` branch with a marketplace.json named swarm-dev-pre whose source is the prerelease ref. It never moves after.
- You add a ruleset on stable and prerelease: no deletion; only you and the lead push stable; release.yml's token may update prerelease; a force-push by the lead is allowed, for rollback (HLD:504-505).
- Lead: open the marketplace.json PR. You merge it, once stable exists.
- Lead: run the proof on a public throwaway copy, the move back included.
- You merge every PR here that changes .github/.
- You add the build check to main's required checks once it has reported on a story PR and on a bump.
- Lead, optional: try one plugin per project and record the answer (open question 4).
- Carve-out (HLD:480-485): none by its wording. The workflow and the build check are no gate of `merge --release`, and you merge every PR that changes them anyway (.github/ is protected).
- Lead: create `stable` and `prerelease` at the newest v0.31.x tag on origin when the story runs, not at v0.31.2: ship-gates cuts a later v0.31.x with the dropped-lines fix (critic).

**Areas:**
- .github/workflows/release.yml
- .github/workflows/ (build check)
- .claude-plugin/marketplace.json
- the stable, prerelease and pre-marketplace branches
- docs/reference-merging.md (release section)
- docs/lead-by-hand.md (rollback)

**Shared rules cited above:**
- L2: Lead: cut a v0.32.x patch to the prerelease ref as ports merge (HLD:307). If the swarm stalls, revert or fix the port on main, move the ref back and restart the sessions (HLD:433-436). After each patch, and before and after each stable move, the lead checks that stable and prerelease point at their expected tags: the lead and every agent share one gh login, so the ruleset cannot tell an agent's push from the lead's.

## Spike results (release-ref-spike, 2026-11-21)

The lead ran release-ref-spike on the public copy https://github.com/redscaresu/swarm-dev-release-spike, made from swarm-dev's main (c3f732cd) and the tags v0.31.0 to v0.31.3.
The copy is kept: release-install-proof, release-publish-proof and release-client's real-release check use it.
Its Dependabot config was removed on the copy's main, so no update PRs open there.

Branches, created before any ruleset and each read back with 200:
- stable: cfe2a200 (v0.31.2)
- prerelease: cfe2a200 (v0.31.2)
- pre-marketplace: ba2d21f2, one orphan commit

The move credential is `github.token`. No `release` environment or `PRERELEASE_PUSH_KEY` is needed.
With no ruleset, the token's fast-forward of prerelease from v0.31.2 to the copy's main passed, across a range that changes `.github/workflows/` (build-check.yml, ci.yml, go.yml, macos.yml and speed.yml): https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/44889504617 (cfe2a200 to c046ae95).
The workflow (`.github/workflows/ref-move.yml` on the copy's main) runs `gh api -X PATCH repos/<repo>/git/refs/heads/<branch> -f sha=<sha> -F force=<bool>` (or `-X DELETE`) with `permissions: contents: write`.

The rulesets, as GitHub read them back:

```json
{"id":27788795,"name":"no-delete","enforcement":"active","include":["refs/heads/stable","refs/heads/prerelease","refs/heads/pre-marketplace"],"rules":["deletion"],"bypass":[]}
{"id":27788796,"name":"locked","enforcement":"active","include":["refs/heads/stable","refs/heads/pre-marketplace"],"rules":["update","non_fast_forward"],"bypass":["RepositoryRole:5:always"]}
{"id":27788798,"name":"prerelease-ff","enforcement":"active","include":["refs/heads/prerelease"],"rules":["non_fast_forward"],"bypass":["RepositoryRole:5:always"]}
{"id":27788799,"name":"main-pr","enforcement":"active","include":["refs/heads/main"],"rules":["pull_request","deletion","non_fast_forward"],"bypass":["RepositoryRole:5:always"]}
```

RepositoryRole 5 is the admin role. main-pr stands in for the real repo's main protection, so a refused push to main can be shown.

Under the rulesets, with `github.token` (each refusal is HTTP 422, and the ref read after it is the SHA read before):
- Fast-forward prerelease, cfe2a200 to 16332d9b: allowed. https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/44889809328
- Force prerelease back to cfe2a200: refused, "Cannot force-push to this branch". https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/44890012798 (stays 16332d9b)
- Update stable to 16332d9b: refused, "Cannot update this protected ref." https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/44890023805 (stays cfe2a200)
- Update pre-marketplace to 16332d9b with force: refused, "Cannot update this protected ref." and "Cannot force-push to this branch". https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/44890036566 (stays ba2d21f2)
- Fast-forward main to a child commit 042726e0: refused, "Changes must be made through a pull request." https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/44890045159 (stays 16332d9b)
- Delete stable, prerelease and pre-marketplace: each refused, "Cannot delete this branch". https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/44890559397, https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/44890568489, https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/44890580287

As the lead (the admin role), through `gh api`:
- Force-push prerelease back one commit, 16332d9b to c046ae95 (the rollback): allowed.
- Delete stable, prerelease and pre-marketplace: each refused, 422 "Cannot delete this branch".

After the tests: main 16332d9b, stable cfe2a200, prerelease c046ae95, pre-marketplace ba2d21f2.

## release-refs results (2026-11-21)

The user created the branches and rulesets on redscaresu/swarm-dev from the lead's commands. The lead read them back the same day:
- stable: 06b35a67 (v0.31.3)
- prerelease: 06b35a67 (v0.31.3)
- pre-marketplace: 653d9366, one signed orphan commit (GitHub: verified). Its `.claude-plugin/marketplace.json` is named `swarm-dev-pre`, with one plugin whose source is `{source: url, url: https://github.com/redscaresu/swarm-dev.git, ref: prerelease}`. It passed the pinned validator (`@anthropic-ai/claude-code@2.1.284 plugin validate`) before the push.

The rulesets, as GitHub read them back:

```json
{"id":27812527,"name":"no-delete","enforcement":"active","include":["refs/heads/stable","refs/heads/prerelease","refs/heads/pre-marketplace"],"rules":["deletion"],"bypass":[]}
{"id":27812633,"name":"locked","enforcement":"active","include":["refs/heads/stable","refs/heads/pre-marketplace"],"rules":["update","non_fast_forward"],"bypass":["RepositoryRole:5:always"]}
{"id":27812756,"name":"prerelease-ff","enforcement":"active","include":["refs/heads/prerelease"],"rules":["non_fast_forward"],"bypass":["RepositoryRole:5:always"]}
```

They match the spike's rulesets above. Main's ruleset 24181590 is unchanged.

## release-install-proof results (2026-11-22)

The lead ran these on the throwaway copy, each install in a throwaway CLAUDE_CONFIG_DIR, with Claude Code 2.1.330.

- **Validator:** the copy's PR #2 set marketplace.json's plugin source to `{source: url, url: <copy>.git, ref: stable}`. Its plugin-validate job, the pinned 2.1.284, passed: https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/44955930947/job/137003929907. The user merged it.
- **Install:** the copy's marketplace was added as users add one (`claude plugin marketplace add redscaresu/swarm-dev-release-spike`). `swarm-dev@swarm-dev` installed 0.31.3 from the copy's main (16332d9b), with bin/swarm.sh hashing to e1c17f83.
- **The marketplace change:** after PR #2 merged, `marketplace update` and `plugin update` moved the install from 0.31.3 to 0.31.2, because the lead had set stable at v0.31.2, one version behind main. That is a downgrade, so the real stable must start at the version users already run (release-refs set it at v0.31.3).
- **Same version, another commit:** with stable moved to another commit at the same version (3ed134ce, 0.31.3), the update printed "already at the latest version". The version, commit (06b35a67) and files stayed. The update moves only on a version change.
- **prerelease forward:** prerelease moved to v0.31.3 while the install followed stable at 0.31.2. The update said "already at the latest version", and nothing moved.
- **stable forward:** the positive control. stable moved to v0.31.3, and the update moved the install to 0.31.3 (06b35a67).
- **Rollback:** swarm-dev@swarm-dev-pre, from the copy's pre-marketplace branch, installed version B: 0.31.3, commit 051371a6, with a marker line in hooks/lead-stop.sh. The admin role force-pushed prerelease back to A (v0.31.2, cfe2a200). `marketplace update` and `plugin update` then moved the install to 0.31.2 at cfe2a200, and the marker was gone from the active hook. No uninstall or cache clear was needed: the update rewrites the install path, which a restart loads.
- **Binary half:** proved in release-client's real-release check, as the user agreed.
- **Rollback entry's issue:** https://github.com/redscaresu/swarm-dev/issues/1116

## release-marketplace results (2026-11-22)

- #1118 set main's marketplace.json plugin source to `{"source": "url", "url": "https://github.com/redscaresu/swarm-dev.git", "ref": "stable"}` and added the stable and prerelease paragraph to docs/reference-merging.md § Releases. plugin-validate was green on it. The user merged it as ab1af7ec.
- A fresh install from redscaresu/swarm-dev, in a throwaway CLAUDE_CONFIG_DIR (`claude plugin marketplace add redscaresu/swarm-dev`, then `claude plugin install swarm-dev@swarm-dev`), installed 0.31.3 at 06b35a67, which is stable's version and commit.
- The lead's own install is 0.31.3 at 06b35a67, stable's version. An update moves an install only on a version change (release-install-proof), so it keeps its version. The lead did not run an update on its real install, because agents run from it.
- stable and prerelease both still name v0.31.3 (06b35a67).

## release-publish-proof results (2026-11-22)

The lead ran these on the throwaway copy, after making its main swarm-dev's main (b39af2c7, with .github/dependabot.yml then removed) and putting its prerelease at v0.31.3. The copy's no-delete, locked and prerelease-ff rulesets match swarm-dev's.

- **First:** swarm-dev's release.yml run on the push that merged release-workflow (7a92db77) printed `steps=none (the version "0.31.3" at 7a92db7 is BEFORE's: no bump)`. Its build and publish steps were skipped, and no release or ref changed: https://github.com/redscaresu/swarm-dev/actions/runs/44923771067
- **(1) build-check:**
  - On a PR with no bump it was green with its build steps skipped: https://github.com/redscaresu/swarm-dev-release-spike/pull/3, https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45012783428
  - On a bump PR it was green and built: https://github.com/redscaresu/swarm-dev-release-spike/pull/4, https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45012796561
  - On a bump PR with a Go file that fails only on linux/arm64 it was red, with `cmd/swarm/proof_arm64.go:6:18: undefined` after the `build: linux/arm64` line: https://github.com/redscaresu/swarm-dev-release-spike/pull/5, https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45012809317
- **(2a) a failed verify:** 0.31.4 had a copy-only build step that appended a byte to swarm-linux-amd64 after the checksum check. The publish job failed at "dist/ holds what scripts/build.sh --list names and the sums pass". No attest, draft, attach, publish or move step ran, there was no draft, and prerelease stayed at 06b35a67: https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45012895319. The step was then dropped by a push with no bump, which printed none: https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45013246252
- **(2) the publish, and (6):** 0.31.5's build job had `contents: read`. Its publish job verified, attested, drafted, attached and published v0.31.5, then moved prerelease last, to 80cfab2d: https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45013393855. That move was the first, and it crossed a range that changes .github/workflows/, under the copied rulesets, which is (6). Every downloaded asset passed `sha256sum -c SHA256SUMS` and `gh attestation verify <asset> --repo <copy> --signer-workflow <copy>/.github/workflows/release.yml`.
- **(3) a blocked move:** the lead added a temporary `update` rule on the copy's prerelease, then pushed 0.31.6. v0.31.6 was published. The move failed with "Repository rule violations found (HTTP 422)", and prerelease stayed at 80cfab2d: https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45013951790. A push with no bump then printed none and was green: https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45014139051. With the rule lifted, "Re-run all jobs" (attempt 2 of 45013951790) planned only `move`. Nothing was built, prerelease moved to a6ceab7d, and the five asset ids were unchanged.
- **(3b) a cancelled publish:** the first try, 0.31.7, cancelled too late: that run had already published and moved, and its rerun printed none (https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45014277300). 0.31.8 then had a copy-only 120 s pause after the draft step. It was cancelled with a draft holding 0 assets. "Re-run all jobs" planned `attach publish move`, attached all five files, published, and moved prerelease to aec9dfef: https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45014532670. The pause was then dropped.
- **Rollback:** the admin role force-moved the copy's prerelease back one version, from v0.31.8 to v0.31.7 (097c6ca7). It was allowed. The next push, with no bump, printed none and left prerelease at 097c6ca7: https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45014895429
- **Time from push to ref move:** 0.31.5 was pushed at 10:37:58Z, and its run ran from 10:38:03Z to 10:43:48Z. That is about 5 min 50 s, under merge --release's 600 s wait.
- **swarm-dev's refs:** stable and prerelease both still name 06b35a67 (v0.31.3), as at the start.
- The copy is kept. Its PRs #3 to #5 are left open, unmerged.

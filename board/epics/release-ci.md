---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [go-module]
stage: v0.32.0
---

# Goal 4, the publishing half

A release publishes four checked binaries and only then moves the prerelease ref. Every install follows the stable ref, and a rollback moves a ref back.

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** On a public throwaway copy of the repo: (1) The build check reports on every PR. It passes on a story PR that is no bump, builds the four binaries in a read-only job on a version-bump PR, and stays red when one platform fails to build. (2) After the merge the workflow builds again in a read-only job. A second job attaches the four binaries, their SHA-256 checksums and a build attestation, and only then moves the prerelease ref. Each of the four downloaded assets passes `sha256sum -c` and `gh attestation verify` with release.yml as the signer. (3) A failed publish leaves the ref where it was, and a rerun after a publish that failed once the release existed attaches the files and moves the ref. (4) A marketplace added the way users add it today installs what the stable ref holds and does not move when prerelease moves. (5) With prerelease moved back one version, an update and a restart bring back the older plugin.json, hooks and binary. If Claude Code does not go back, docs/lead-by-hand.md has the rollback that does, before any port merges. (6) The workflow's push to prerelease works under the rulesets on stable and prerelease, and the pinned plugin validator passes main's marketplace.json. An install on that v0.31.x tag does not move when the marketplace.json PR merges.

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

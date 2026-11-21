---
kind: lead
status: ready
epic: release-ci
depends_on: []
touches: [the throwaway copy (a new public repo), redscaresu/swarm-dev: the release environment and its deploy key (only if the token is refused)]
estimate_lines: 0
easy: true
risk: high
---

# Lead: on a public throwaway copy, prove how the release workflow can fast-forward prerelease across a workflow change, under the candidate rulesets

Needs no other story. Run it first: release-refs, release-install-proof and release-workflow use its answers.
- Lead: create a public repo under the same account (the epic: attestations need a public repo) and push origin/main and the v0.31.* tags to it. Write its name in this story file. Keep it: release-install-proof, release-publish-proof and release-client's real-release check (release-client.md Done when 5) all use it.
- Lead: on the copy, create all three branches before any ruleset: stable and prerelease at v0.31.2's commit, pre-marketplace as one orphan commit. Read each back (`gh api repos/<copy>/branches/<b>`, 200) and record its SHA, so no later refusal can be a 404 on a missing ref (codex).
- Lead: add a workflow_dispatch workflow to the copy's main only, with `permissions: contents: write`, that runs `gh api -X PATCH repos/<copy>/git/refs/heads/prerelease -f sha=<main tip> -F force=false` with github.token. Main's range since v0.31.2 changes files under .github/workflows/ (go.yml and macos.yml are new). Run it once with no ruleset, then set prerelease back. Why: I believe GitHub refuses a ref update by the Actions token when the range changes a workflow file (no `workflows` permission). Untested; v0.32.0's first move crosses such changes.
- Lead: add the candidate rulesets. (a) No-delete on stable, prerelease and pre-marketplace: `deletion`, no bypass. (b) On stable and pre-marketplace: `update` and `non_fast_forward`, bypass the repository admin role (always). (c) On prerelease: `non_fast_forward`, bypass the admin role (always). Record the JSON.
- If the token's fast-forward was refused: **You:** on the copy and on redscaresu/swarm-dev, create an environment named `release` whose deployment branches are main only, add a deploy key with write access, and put its private half in that environment's secret `PRERELEASE_PUSH_KEY`. Never a repository secret: every same-repo pull_request run can read one, and every agent pushes same-repo branches (critic). The lead never sees it. Lead: switch the dispatch workflow to an SSH push with that secret, under `environment: release`.
- Lead, under the rulesets, with the credential release-workflow will use (the token, or the deploy key) (codex): its fast-forward of prerelease (expect allowed); its force move back (expect refused); its push to stable, to pre-marketplace and to main (expect refused); its deletion of each branch (expect refused). Then as the lead: a force-push of prerelease back one commit (expect allowed: the rollback) and a deletion of each branch (expect refused). With the deploy key, also a same-repo PR job that names `environment: release` (expect refused by the branch policy).
- Each refusal records GitHub's rule message (a repository rule violation naming the rule, not a 404) and the ref's SHA read before and after, unchanged.
- Change nothing on redscaresu/swarm-dev but the You: step's environment and key.

The throwaway repo starts with no branch protection, since pushing history copies no rulesets. Before testing push refusal, add a ruleset on the copy's main (no direct push, pull request required) as well as the candidate rulesets on stable and prerelease, so a refused push can be shown (codex).

**Done when:**
- This story's file records the copy's name and each branch's SHA before the rulesets. With a run URL or command output each, it records: whether the token's fast-forward of prerelease across a range that changes .github/workflows/ passed with no ruleset, or GitHub's refusal; the ruleset JSON; for the credential release-workflow will use, its allowed fast-forward and each refused force move, push and deletion, each with GitHub's rule message and the ref's SHA unchanged; the lead's allowed force-push and refused deletions; and, if the deploy key is used, the environment's branch policy, the secret's name and the refused PR job.

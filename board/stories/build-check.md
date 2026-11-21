---
kind: code
status: ready
epic: release-ci
depends_on: []
touches: [.github/workflows/build-check.yml, docs/reference-merging.md:§ The build check (new, right before § The retro gate)]
estimate_lines: 70
easy: true
---

# A build-check job reports on every PR and builds the four binaries on one that changes plugin.json

Needs no other story. The user merges it (.github/ is held).
- A new file, not release.yml: release.yml is the attestation signer (scripts/build.sh:21; tests/build_test.sh:54-55), and a pull_request run must never share it.
- Triggers: go.yml:4-11's pull_request types and merge_group, and no push. go.yml's build-contract step already builds the four and checks their sums on every push to main (go.yml:106-119), and release.yml builds on a bump's push (codex, critic). Top-level `permissions: contents: read`; checkout with fetch-depth 0 and persist-credentials: false; the setup-go pin from go.yml:60 with `cache: false` (go.yml:63; skeptic-release-workflow). The job id is `build-check` and its only permission is contents: read.
- The gate skips steps, never the job (go.yml:21-23): a required check that never reports blocks the PR, and wait-pr exits 2. Do not reuse board-only.sh's verdict: it is `true` on a version-only bump (board-only.sh:41-61), the one PR this must build.
- Build when the event's `git diff --name-only --no-renames <base>...HEAD` names .claude-plugin/plugin.json, the base taken as go.yml:51 takes it; or when there is no base SHA, or the diff fails or is empty (fail closed). Otherwise skip, with a log line saying the PR does not change plugin.json.
- Build: `scripts/build.sh`, then dist/ holds exactly what `--list` names and `sha256sum -c SHA256SUMS` passes (the check at go.yml:106-119). build.sh already exits non-zero when one platform fails (build.sh:49-52).
- Before the PR opens, run actionlint (a pinned release, named in the PR) on build-check.yml: CI's shellcheck reaches only *.sh files (ci.yml:41), and actionlint checks expressions and shellchecks run: blocks.
- Prove it with two tmp/ PRs from this branch, closed unmerged and their branches deleted after: one that only bumps the version, and one that bumps it and adds a Go file that fails to compile only under `//go:build linux && arm64`. Put both run URLs in this PR's body.
- docs: a short `### The build check` saying what it builds, when it skips, and that it does not run on main's push. Run the humanizer pass and say so in the PR.

**Done when:**
- On this story's PR, build-check reports success with its build steps skipped and the skip line in its log. On the version-bump tmp/ PR it builds the four assets `scripts/build.sh --list` names and the checksums pass. On the tmp/ PR that breaks linux/arm64 it is red and names linux/arm64. The workflow has no push trigger, its only permission is contents: read, setup-go has cache: false, zizmor is green, and actionlint reports nothing on it, with its version and output in the PR. Both tmp/ PRs are closed unmerged, and doc_check passes.
- scripts/select-tests.sh --run passes

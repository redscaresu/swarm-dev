---
kind: code
status: blocked
epic: release-ci
depends_on: [publish-plan, release-ref-spike]
needs: publish-plan (scripts/publish-release.sh plan, and the steps= and tag= lines it writes); release-ref-spike (how the move pushes prerelease: github.token, or the PRERELEASE_PUSH_KEY secret in the release environment)
touches: [.github/workflows/release.yml, docs/reference-merging.md:§ Publishing a release (new, after § The retro gate, before § Commands)]
estimate_lines: 170
risk: high
---

# release.yml builds in a read-only job, then a publish job verifies, attests, attaches and publishes, and only then moves prerelease

Uses publish-plan's `scripts/publish-release.sh plan` and the move method release-ref-spike recorded (github.token; board/epics/release-ci.md § Spike results). The user merges it (.github/ is held). publish-plan-recover changes no line the plan writes, so this story does not wait for it.
- Keep the path and the push-to-main trigger: release.yml is the signer `--list` names (build.sh:21; build_test.sh:55). Keep the `release` concurrency group (release.yml:14-17).
- Job `build`, contents: read only: checkout at the pushed SHA with fetch-depth 0 (the plan reads BEFORE's plugin.json) and persist-credentials: false; run plan with REPO, SHA and BEFORE = github.event.before. When its steps contain `attach`: set up Go from go.mod with the setup-go pin from go.yml:60 and `cache: false` (go.yml:63; skeptic-release-workflow); run `scripts/build.sh`; check dist/ against `--list` and `sha256sum -c`; upload dist/ with the upload-artifact pin from scorecard.yml:52, retention-days 1. Output steps and tag.
- Job `publish`, needs build, runs only when build's steps are not `none`. It alone has contents: write, id-token: write and attestations: write, set on the job (zizmor). It checks out, runs plan again with its write token (only that token sees drafts) and acts only on what that plan prints.
- Order, each step gated on the publish job's plan. When it contains `attach`: download the artifact, verify the files against `--list` and SHA256SUMS, and attest the four binaries, all before anything is drafted, so a bad artifact leaves no draft (codex, skeptic-release-workflow). Then `draft` (`gh release create <tag> --draft --target <SHA> --generate-notes`); `attach` (all five, `--clobber`, on a draft only); `publish` (`--draft=false`, which creates the tag); `move`, fast-forward only, last, which reads the ref back and prints where it moved. On a move-only run nothing is downloaded, verified or attested. No step's if: uses always(), failure() or !cancelled(), so a failed step stops the job and the ref stays where it was.
- If the move uses the deploy key, the publish job names `environment: release` and a missing secret fails red, never skips (rules.md: a no-secret skip never shares the fail-closed guard).
- New actions (download-artifact, attest-build-provenance) are pinned to a SHA with a version comment. Every checkout has persist-credentials: false.
- release-client's release check waits for the moment the ref moves (release-client.md Done when 4), which is why the move comes last.
- Before the PR opens, run actionlint (a pinned release, named in the PR) on release.yml: CI's shellcheck reaches only *.sh files (ci.yml:41), while actionlint checks needs and outputs names, if: expressions and the run: blocks (skeptic-release-workflow).
- docs: `### Publishing a release`: the two jobs and the order; that a push with no bump makes no gh call; that a rerun is 'Re-run all jobs', since the artifact lasts one day and the build job rebuilds when the plan still needs attach (critic); that a rerun finishes what a failed run left and never replaces a published file; that a red run on a bump's push is re-run the same way; that it never moves stable; and that a rerun after a rollback moves prerelease forward again. doc_check; humanizer pass, said in the PR.
- No AGENTS.md edit: AGENTS.md:316-318 ('publishes the release and its tag') stays true, and release-client owns that paragraph (release-client.md:43).

**Done when:**
- zizmor is green on the PR, and actionlint reports nothing on release.yml, with its version and output in the PR. The build job's only permission is contents: read. The publish job alone has contents: write, id-token: write and attestations: write, at job level. Every action is pinned to a SHA, every checkout has persist-credentials: false, and setup-go has cache: false. In the publish job, download, verify and attest run only when its own plan printed attach, and come before draft. draft, attach, publish and move each run only when that plan printed them, in that order. No step's if: uses always(), failure() or !cancelled(), and the move is last. docs/reference-merging.md § Publishing a release states the order, 'Re-run all jobs' as the rerun rule and that stable never moves here, and doc_check passes. The run proof is release-publish-proof.
- scripts/select-tests.sh --run passes

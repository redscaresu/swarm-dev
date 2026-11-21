---
kind: docs
status: blocked
epic: release-ci
depends_on: [release-install-proof, release-workflow]
needs: release-install-proof (whether an update and a restart go back, or the steps that did, and the issue URL); release-workflow (the rerun rule in § Publishing a release: 'Re-run all jobs' finishes a release and moves prerelease forward again)
touches: [docs/lead-by-hand.md:§ Rolling back the prerelease (new, at the end), docs/lead-by-hand.md:opening line (as of v0.31.0)]
estimate_lines: 20
easy: true
---

# docs/lead-by-hand.md has the prerelease rollback that release-install-proof showed works

Uses release-install-proof's recorded rollback steps and issue URL, and release-workflow's rerun rule. It must merge before any port does (Done when 5).
- Add `## Rolling back the prerelease` at the end, in the file's Symptom / Step / Issue form (docs/lead-by-hand.md:16-20).
- Symptom: a port released to prerelease stalls the swarm.
- Step, in order: revert or fix the port on main first, since the next release moves prerelease forward past the rollback; move prerelease back to the last good release's tag commit with the lead's force-push; then the update, restart or other steps the proof recorded; then check stable and prerelease against their tags (L2). Do not re-run the release run of the version rolled back from, in either form: a rerun finishes that release and moves prerelease forward again.
- Issue: the URL release-install-proof opened.
- Change the opening line's `as of v0.31.0` to v0.32.0. release-client adds its own entry later, after this one.
- Humanizer pass, said in the PR.

**Done when:**
- docs/lead-by-hand.md ends with the section in Symptom / Step / Issue form. Its steps match the ones release-install-proof recorded, it warns against re-running the rolled-back version's release run, and its Issue line links the issue release-install-proof opened. doc_check passes.
- scripts/select-tests.sh --run passes

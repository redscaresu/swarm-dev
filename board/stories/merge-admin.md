---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/*.sh (the merge command and config defaults), docs/reference.md (config table), tests/merge_test.sh]
easy: true
estimate_lines: 60
---

# merge = agent works on a repo whose ruleset requires an approving review

infrafactory's first `merge = agent` run (2026-10-17) merged nothing. Its ruleset requires one
approving review, `swarm.sh merge` runs `gh pr merge` without `--admin`, and GitHub refused both
PRs (#602, #603) with "To use administrator privileges ... add the `--admin` flag." The lead then
merged both by hand with `--admin`. A builder cannot approve its own PR, and the codex reviewer
leaves no GitHub review, so the rule can never be met by the swarm.

Add a setting `merge_admin` (default `off`). When `on`, `swarm.sh merge` passes `--admin` to
`gh pr merge`, and only after its own checks have passed: the head is green (`ci_gate head`), the
`costs: money` hold, and `--board`/`--release` scoping. Nothing else changes: a red head, a held
PR, or a head that moved still refuses. Document it in the config table with that condition.
Off by default, so merging changes nothing; turning it on for infrafactory is the lead story
merge-admin-on-for-infrafactory.

**Done when:**
- With `merge_admin = on`, a test shows `gh pr merge` called with `--admin`; with it off, without.
- With it on, a red head, a `costs: money` PR and a moved head are each still refused before `gh pr merge` runs (one test each).
- `swarm.sh config merge_admin` prints `off` in a project that does not set it.

It ships in release-safety: that release also ships merge-guard-hook (#242), which blocks the lead's
hand `gh pr merge --admin`, so without this story nothing could merge in a repo that requires an
approving review.

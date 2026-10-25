---
kind: docs
status: blocked
epic: stage-gating
depends_on: [stage-release-gate]
needs: [stage-release-gate: the `release v<S>` step and the `release-held:` line in bin/lib/board.sh:next_step and next_report]
touches: [commands/swarm.md:release arm, tests/merge_test.sh:release arm checks, docs/reference.md:Releases release PR body]
estimate_lines: 30
easy: true
---

# The release arm says when a stage release is cut and what its PR body lists

Needs stage-release-gate's `release v<S>` step and `release-held:` line (bin/lib/board.sh:next_step, next_report). In commands/swarm.md's release arm (:276-330) say three things: a stage release is a minor, the v<S> next names; it is cut only when next prints `release v<S>`, and while next prints `release-held:` no minor is cut (a patch for an urgent fix is then the user's call); the release PR body lists the behaviour changes every project gets on upgrade and names the infrafactory build they were tried on, or says none. Add the PR-body sentence to docs/reference.md § Releases. Keep the heading `` `release`: ``, which tests/merge_test.sh:1929 reads.

Review fix (critic): docs/reference.md § Releases says the stage hold lives in next only: merge --release does not read it, so the lead cuts a release only when next prints it. When the lead files the per-stage release stories, their flip step points at this epic's `stage` arm.

**Done when:**
- tests/merge_test.sh's release-arm checks (:1929-1941) grep the three statements: a minor at v<S>; cut only on `release v<S>`; the PR body's behaviour changes and the infrafactory build or none. Each goes red when its sentence is removed, and the existing checks still pass.
- command_names_test and doc_check pass.

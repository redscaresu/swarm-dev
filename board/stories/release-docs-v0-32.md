---
kind: docs
status: ready
touches: [README.md, AGENTS.md:Working on this repository, docs/lead-by-hand.md, docs/method.md, docs/reference.md]
estimate_lines: 150
easy: false
---

# Bring the docs in line with everything merged since v0.31.3

From the v0.32.0 retro. Before the v0.32.0 cut, `swarm.sh merge --release` needs README.md, AGENTS.md and docs/ in line with every change merged since the v0.31.3 tag (`git log v0.31.3..origin/main`). Go through each merged PR and fix every line in those files that is now false or missing. AGENTS.md's Go layers bullets name the Go checks merged since v0.31.3: the process-start check (#1165), the deadline check (#1167) and the variable-pattern check (#1166). docs/lead-by-hand.md says that a newly required check means rebasing every open PR branched before it (#557, replaced by #1161). Run the humanizer over the changed prose.

**Done when:**
- Each PR merged since v0.31.3 that changed what a user runs, sees or must do has its doc line in README.md, AGENTS.md or docs/, and the PR body lists them.
- AGENTS.md names the three Go checks; docs/lead-by-hand.md has the required-check rebase line.
- tests/doc_check_test.sh passes.

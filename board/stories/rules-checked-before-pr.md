---
kind: code
status: ready
depends_on: []
touches: [bin/swarm.sh, tests/, docs/method.md, README.md]
---

# A builder checks its diff against every lesson rule before it opens the PR, and says so in the PR body

On 2026-10-14 `swarm.sh lessons` on infrafactory reported 7 kinds still recurring after their rule landed in AGENTS.md: docs-misstate-code (fixed in 39 PRs since), fails-open (27), vacuous-test (23), state-duplication (17), regression-from-fix (12), denylist (8) and unbounded-call (3). A rule pasted into the brief does not stop the mistake; review catches it after the PR is open. So the lead adds no more rules for now and closed the open rule PRs (infrafactory #485–487) instead. This story turns the existing rules into a step.

When project_rules (bin/swarm.sh:1536) prints any tagged rule (`<!-- lesson: <kind> -->`), the builder brief (story_brief, and the second caller at :1636 if it is a builder prompt) adds one instruction after the rules. Before opening the PR, walk the diff against each rule. The PR body then gets a `Rules checked:` section with one line per kind: what in the diff was checked (file:line), or `n/a: <why>`. With no tagged rule, nothing is added. The conductor's review treats a PR without that section, or with a line that names nothing, as a finding of kind `rules-unchecked`. That review is the reviewer brief (or conduct mode) that already sends findings back. docs/method.md and README say this where they describe the brief and the outer loop; README prose goes through humanizer:humanizer. bash 3.2.

**Done when:**
- A test with a lessons_file holding two tagged rules shows the builder brief carrying the step and both kinds; a test with no tagged rule shows no step. Both fail if the step is removed or always printed.
- The reviewing prompt (whichever sends findings back) names the `rules-unchecked` kind, pinned by a test.
- docs/method.md and README describe the step; every tests/*_test.sh and `claude plugin validate .` pass.
- After it ships, `swarm.sh lessons` on infrafactory is the measure: a recurring kind's "fixed in N PRs since" count stops growing on PRs built with the step. That is checked by the lead later and is not part of this PR.

---
kind: code
status: ready
depends_on: []
touches: [bin/lib/merge.sh:merge_pr ci_gate call, bin/lib/build.sh:review_recheck ci_gate call, bin/lib/lifecycle.sh:heads_green ci_gate call, tests/merge_rules_test.sh:expected-workflow cases, docs/reference-merging.md:merging paragraph (§ Merging) expected-workflow sentence]
estimate_lines: 120
easy: false
risk: high
---

# Every ci_gate head call waits on the workflows a PR's pull_request runs

The v0.31.0 retro (2026-11-17) found three `ci_gate head` calls that pass only `<repo> <sha>`, so
ci_gate checks the check runs that exist and never the workflows the PR's `on: pull_request` should
start: bin/lib/merge.sh:1182 (the merge's own green check), bin/lib/build.sh:1110 (review-agent
--recheck) and bin/lib/lifecycle.sh:2752 (heads_green, the lead queue's green read). A head whose expected
workflow never started reads green there. `wait-pr` passes base, PR and changed files
(bin/lib/merge.sh:54-62), and usually runs first, but nothing makes it.

Pass `<base> <pr> <changed>` (and the memo file where the caller has one) at all three sites, the way
wait-pr does, so a head with an expected workflow that has no run on it reads pending, not green. The
user chose to fix this before v0.31.0 is cut.

**Done when:**
- tests/merge_rules_test.sh: a fixture PR whose head has green check runs but no run of a workflow its
  pull_request covers makes `swarm.sh merge` refuse it as not green, naming the workflow; with the
  change removed the merge goes ahead (shown on a worktree copy, quoted in the PR)
- review-agent --recheck refuses the same head, and the lead queue does not count it green (a case each)
- A head where every expected workflow ran green still merges
- docs/reference-merging.md says merge, the recheck and the lead queue wait on the PR's expected
  workflows as wait-pr does
- scripts/select-tests.sh --run passes

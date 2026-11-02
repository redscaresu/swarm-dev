---
kind: docs
status: ready
epic: merge-mechanics
depends_on: []
touches: [docs/reference-merging.md:Merge queue, docs/features.tsv:Goal 12 row]
estimate_lines: 30
easy: true
---

# Docs: how to turn on a merge queue, and the Goal 12 row in features.tsv

Merge-queue routing shipped: queue_merge (bin/lib/merge.sh:1981), wired in merge_pr at 1119-1137, documented at docs/reference-merging.md:453-500, tested in tests/merge_queue_test.sh. Left from the epic: how to turn one on. Add to the 'Merge queue' paragraph: the GitHub steps (a ruleset on the base with the merge_queue rule, or branch protection's merge queue), that the required workflows must run on merge_group (as this repo's ci.yml and zizmor.yml do), and that merge_admin = on cannot use one (ci_gate admin refuses a merge_queue rule). Turning it on for swarm-dev itself is the parked lead story board/stories/merge-queue-on.md: out of scope. Add the Goal 12 row to docs/features.tsv: landed merge-mechanics; metric `flow incidents: cause`, the lead-hand incidents with cause story-gone, pr-no-story, no-conductor, classifier or upgrade per build (all five are in INTERVENE_CAUSES, bin/swarm.sh:560); baseline 12 in v0.29.0's notes (HLD Goal 12); bar 0. tests/features_test.sh's section check (125-175) fails on a column flow incidents does not print; it prints `kind cause incidents` (bin/lib/flow_incidents.py:74).

**Done when:**
- docs/reference-merging.md's Merge queue paragraph has the steps to turn one on and says merge_admin = on rules a queue out.
- docs/features.tsv has a row landed merge-mechanics naming `flow incidents: cause`, and tests/features_test.sh passes.
- The PR says the humanizer pass ran on the changed prose.

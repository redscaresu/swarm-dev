---
status: draft
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.31.0
depends_on: []
---

# review-follows-head

Reviews follow the PR's head: a new commit is reviewed, not a reason to stop

HLD § v0.31.0 additions. In the v0.30.0 build reviews stopped at least 5 times: a builder pushed mid-review and the reviewer stopped with no verdict, with nobody to restart it once the conductor had gone; or the reviewer waited up to 30 minutes for a builder whose turn had ended.

**Done when:**
- stage: v0.31.0
- When the PR's head moves during a review, the review agent reviews the new head itself (its round count kept) instead of stopping; a test pushes mid-review and sees a verdict on the new head.
- After sending findings, the review agent waits for a new commit on the PR, not for the builder's turn to end; a test with a builder that has finished sees the review resume within one poll.
- docs/features.tsv row: reviews restarted by hand per build, read from `flow incidents`.

**Out of scope:**
The round cap itself (shipped in v0.30.0).

**Constraints:**
- stage: v0.31.0. From the HLD's v0.31.0 additions (decided 2026-10-31); /plan-epic scopes it.

**Areas:** bin/lib/build.sh (review brief, review_next), bin/lib/lifecycle.sh (review watch), tests/review_*

**Your part:**
- none

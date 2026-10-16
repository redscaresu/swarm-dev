---
kind: lead
status: blocked
blocked_by: [flow-and-features, scoped-parallel-reviews, stacked-start-and-merge-order, stacked-parent-updates, backlog-conductor, plan-during-review-and-release, plan-epic-rules]
epic: leaner-faster-swarm
depends_on: [flow-and-features, scoped-parallel-reviews, stacked-start-and-merge-order, stacked-parent-updates, backlog-conductor, plan-during-review-and-release, plan-epic-rules]
touches: []
---

# After the release, the lead sets each throughput number beside its baseline and acts on the features report

This story starts after release-this-epic is done and one infrafactory epic has run on that release. The lead then runs `swarm.sh flow --since <that epic's first build date>` and `swarm.sh features` in both infrafactory and swarm-dev. On this story it posts, for each throughput change (stacked builds, review agents, the backlog conductor, planning during review, short chains), the number beside its docs/features.tsv baseline, comparing like with like: the review-wait baseline is a proxy, so it is set beside the new proxy column, not the new review-agent wait. A number that did not improve is named, and a story is filed to look into it or to delete the feature. From that epic's events.tsv it also checks that a real conductor reviewed PRs at once: at least two `review-agent` starts before the first of those review agents closed. Each `delete?` row in either project's features report is filed as a deletion story, which checks both projects first, or kept with a reason. infrafactory stays merge = human as always; nothing here is the user's.

**Done when:**
- This story holds both projects' flow output for the window, with each throughput number beside its baseline.
- Each change whose number did not improve is named here, with its filed story linked.
- The events.tsv lines showing at least two review agents started before the first of them closed are quoted here, or a story is filed saying why they were not.
- Both projects' features output is posted, and each `delete?` row has a filed deletion story or a reason to keep it.

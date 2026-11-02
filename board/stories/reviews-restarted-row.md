---
kind: code
status: ready
epic: review-follows-head
depends_on: []
touches: [bin/swarm.sh:INTERVENE_CAUSES, commands/swarm.md:intervene cause list, docs/features.tsv:reviews restarted by hand row (new), tests/intervene_test.sh:cause count and review-stopped check]
estimate_lines: 25
easy: true
---

# features.tsv row for reviews restarted by hand, and the intervene cause review-stopped

No intervene cause covers a review the lead had to start again. There were five such cases in the v0.30.0 build. Two reviews waited on a builder that had already finished: #758 at 2026-10-30T13:17:36Z and #765 at 2026-10-30T21:06:02Z. Three reviews stopped when the builder pushed mid-review: #792 at 2026-10-31T08:09:21Z, #794 at 12:11:16Z and #796 at 15:19:27Z. All five are lead-hand lines in .swarm/events.tsv with no cause= field, so flow incidents (bin/lib/flow_incidents.py:67-80) counts them under cause `-`. Add `review-stopped` to INTERVENE_CAUSES (bin/swarm.sh:560), before `other`. Add it to the cause list in commands/swarm.md (:728-731), described as a review the lead started again by hand because it stopped on a moved head or waited on a builder that had finished. Update the cause count check at tests/intervene_test.sh:39 (20 becomes 21) and add a check that logs one review-stopped line. Add the docs/features.tsv row: feature `reviews restarted by hand`; landed `review-follows-head`; metric `flow incidents: incidents on the lead-hand review-stopped row, per 100 builds`; baseline `5 in the v0.30.0 build (lead-hand lines 2026-10-30 to 2026-10-31, logged with no cause) over 103 builds (HLD v0.31.0 additions); bar 0`; uses `unlogged: a followed head is a review-agent:next line like any round's`. tests/features_test.sh's section check (:161-190) reads the word after the colon, `incidents`, which is a header flow incidents prints. Read the baseline from the lines cited here: run no flow, dash or outcomes against the real repo.

**Done when:**
- `swarm.sh intervene lead-hand review-stopped "<line>"` adds one incident with cause=review-stopped, a new check in tests/intervene_test.sh. That check fails with review-stopped taken out of INTERVENE_CAUSES; the PR pastes the FAIL line.
- tests/intervene_test.sh's count check reads 21 causes, and an unknown cause still fails and logs nothing.
- docs/features.tsv has the `reviews restarted by hand` row, and tests/features_test.sh passes, its section check included.
- commands/swarm.md's cause list names review-stopped, and tests/doc_check_test.sh passes.

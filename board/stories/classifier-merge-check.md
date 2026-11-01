---
kind: lead
status: ready
epic: merge-mechanics
after: merge-mechanics
depends_on: []
touches: [docs/lead-by-hand.md:A conductor's merge refused by the permission classifier]
estimate_lines: 10
easy: true
---

# Lead: Find out whether auto mode still refuses a conductor's swarm.sh merge (#699)

#699, a lead story: its cause is unknown, so no mechanism can be named (HLD:462-463); never given to an agent. after: merge-mechanics (it waits until the epic is built). Evidence in .swarm/events.tsv: three lead-hand incidents in the v0.29.0 build name a conductor's swarm.sh merge refused by the classifier (2026-10-26T04:57:59Z, 2026-10-26T09:13:35Z, 2026-10-28T08:59:45Z). Since the v0.29.0 tag (2026-10-28T21:38Z) the log has 87 lead-hand incidents and none names a conductor's merge refused by the classifier; the one that names the classifier (2026-10-31T00:57:52Z) is the lead's own merge of a hooks PR. The preflight for a missing allow rule is MERGE_RULE and merge_allowed (bin/lib/lifecycle.sh:2120, 2142); a classifier refusal is a different cause (auto-denied, docs/reference-logs.md:94).
**You:** at the end of the v0.31.0 build, say whether any conductor reported that auto mode refused its `swarm.sh merge`. If one did, run that conductor's merge command, as its pane shows it, from a conductor pane once more and give the lead the refusal text.
The lead then records here what was refused and why (command form, cwd, a chained command, issue #699's list), or that it did not recur, with the build's incident count. If it recurred, the lead files a kind: code story naming the form to change. If not, the lead closes #699 and removes docs/lead-by-hand.md's 'A conductor's merge refused by the permission classifier' block (67-71) in a PR listed on this story's prs:.

**Done when:**
- This story records the refusal text and its cause, or 'did not recur in the v0.31.0 build' with the build's lead-hand incident count from events.tsv.
- Then either a kind: code story for the fix is on the board, or #699 is closed and docs/lead-by-hand.md has no classifier block.

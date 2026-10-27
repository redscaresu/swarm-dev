---
kind: code
status: blocked
epic: fixes-027
depends_on: [protected-path-hold]
needs: [protected-path-hold (merge-holds): merge_pr's checks after the head's CI, as it leaves them (bin/lib/merge.sh:255-306), less-noise's contents-reader story (no slug yet): the reader behind merge_read]
touches: [bin/lib/merge.sh:merge_pr story path, bin/lib/merge.sh:epic_guard, docs/reference.md:§ Merging epic guard, docs/reference.md:command table merge row, tests/merge_rules_test.sh:story merge epic cases]
estimate_lines: 110
easy: false
risk: high
---

# swarm.sh merge guards a story PR that sets an epic active

Uses merge-holds' protected-path-hold, which edits the same checks in merge_pr (bin/lib/merge.sh:255-306). Merge after less-noise's contents-reader story, since epic_guard reads through merge_read (:141); the lead adds it to depends_on once it has a slug. Today only --board runs epic_guard (:297), so a plain merge of a story PR that flips an epic from draft to active is not checked. List the PR's files on the story path too (ci_gate files, as :280 does) and run epic_guard there. Its refusal keeps the same exit, without the --board: prefix on that path. Update docs/reference.md § Merging (:1948-1950) and the merge row of the command table (:2377).

**Done when:**
- tests/merge_rules_test.sh: a plain swarm.sh merge of a story PR that also sets a draft epic active with no ticket is refused and merges nothing. Fails on the base.
- A story PR that sets a draft epic active with a ticket (an hld: naming an agreed HLD that grants epics) merges.
- The same story PR with the epic left draft merges.

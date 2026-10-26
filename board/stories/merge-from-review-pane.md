---
kind: code
status: ready
epic: review-loop
depends_on: []
touches: [bin/lib/merge.sh:merge_caller, bin/lib/merge.sh:merge_grant header comment, bin/lib/merge.sh:merge_pr caller line, tests/merge_rules_test.sh:Who may merge cases, docs/reference.md:Merging who may merge]
estimate_lines: 140
easy: false
risk: high
---

# swarm.sh merge accepts a review agent's pane for its own story's PR

merge_caller (bin/lib/merge.sh:98-116) takes the PR URL from merge_pr (merge.sh:245). It accepts a pane whose agent is review-<slug> by exact record: the pane's tab record names review-<slug>, the newest .swarm/agents.tsv line for that name has role review, the name does not end -done, and the URL is on story <slug>'s prs: line. Any other PR is refused, and so are --board and --release from a review pane. Under merge = human the existing merge_grant check (merge.sh:302-305) then runs, as it does for every caller. Only merge_grant's header comment changes (it says 'the lead'). A builder pane named review-<x> (a story slugged review-x) stays refused. Add the cases to tests/merge_rules_test.sh's who-may-merge block (merge_rules_test.sh:333-345), not merge_test.sh. Update docs/reference.md § Merging's who-may-merge sentence (reference.md:2100). merge-holds' pinned-head story merges after this one (both edit bin/lib/merge.sh:merge_grant).

**Done when:**
- tests/merge_rules_test.sh: review-a's pane merges story a's PR under merge = agent (exit 0, gh pr merge called).
- review-a's pane is refused when it merges story b's PR, and when it runs merge --board; a check each.
- Under merge = human, review-a's pane merges a's PR when its HLD grants merge, and is refused with merge_grant's 'waits on the user's merge' line when none does.
- A builder's pane is refused under both modes; a pane named review-x whose agents.tsv role is not review, and a review-a-done pane, are refused.
- Dropping the prs: check from merge_caller turns the cross-story case red (falsified once, noted in the PR); tests/doc_check_test.sh passes.

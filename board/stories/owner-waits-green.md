---
kind: code
status: ready
epic: review-loop
depends_on: []
touches: [bin/lib/build.sh:review_brief, bin/lib/merge.sh:wait_pr, docs/reference.md:Building review paragraph, docs/reference.md:The escalation ladder ci-red trigger, tests/escalate_triggers_test.sh:ci-red from review pane cases, tests/review_agent_test.sh:green step checks]
estimate_lines: 170
easy: false
risk: high
---

# The review agent waits for green and triages scanners, and its red heads still step the build up

In review_brief (build.sh:763-818): before each review, and after each push, wait with `swarm.sh wait-pr <PR URL>`. Triage `swarm.sh findings <repo> <pr>` notes and open code-scanning alerts before the head counts green, as green_rule (build.sh:983-990) says, without editing green_rule. A real one goes to the builder as `swarm.sh tell <slug> nudge`; the rest are rebutted with a reason in the PR. A red head or a conflict is a nudge naming the check or the base. The ci-red-2 count: ci_red_scan runs only in a conductor's watch with --epic or --backlog (merge.sh:1527, 1674-1704); the lead's bare watch skips it. So wait_pr (merge.sh:967), when the pane running it is review-<slug>'s (the pane herdr lists for that name; <slug> from the PR's story/<slug> head branch) and escalate_ladder is set, runs ci_red_scan for that story on a red exit, before it exits 1. RED_HEADS counts distinct heads and ladder_step holds a lock, so a conductor's watch scanning too is safe. Document the scan in reference.md § The escalation ladder (reference.md:2505-2509, 'The lead's bare watch steps up nothing'). Merge before merge-holds' wait-pr stale-head story (both edit bin/lib/merge.sh:wait_pr).

**Done when:**
- tests/escalate_triggers_test.sh: with escalate_ladder set and no watch running, wait-pr run from review-<slug>'s pane on the build's second red head steps the build up (escalate 'ok (ci-red-2: ...)').
- The same red heads seen by wait-pr from the builder's pane or the lead's step nothing up and write nothing to .swarm/red-heads.tsv.
- A green head from the review pane writes no red line and steps nothing up.
- tests/review_agent_test.sh pins the wait-pr step and the findings and code-scanning triage in the brief; tests/wait_pr_test.sh passes.

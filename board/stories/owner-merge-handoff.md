---
kind: code
status: blocked
epic: review-loop
depends_on: [owner-findings-rounds, merge-from-review-pane]
needs: [owner-findings-rounds: the pass rule in bin/lib/build.sh:review_brief, merge-from-review-pane: bin/lib/merge.sh:merge_caller accepting the story's review pane]
touches: [bin/lib/build.sh:review_brief, bin/lib/build.sh:review_rule read-only sentence, bin/lib/board.sh:mark_review, bin/swarm.sh:usage header, bin/swarm.sh:review dispatch arm, commands/swarm.md:backlog review arm, docs/reference.md:Building review paragraph, docs/reference.md:Commands review rows, docs/method.md:Build step, README.md:How it works, tests/review_agent_test.sh:handoff cases]
estimate_lines: 240
easy: false
risk: high
---

# On a pass the review agent merges or hands the PR to the user, on the head it reviewed

Uses owner-findings-rounds' pass rule in bin/lib/build.sh:review_brief, and merge-from-review-pane's merge_caller (bin/lib/merge.sh). `swarm.sh review <slug> --head <sha> <url>...` (mark_review, board.sh:1688) refuses when a PR's head is not <sha>, naming `review-agent --next`, and changes nothing. events.tsv's review line keeps its form (slug target, `ok (<urls>)`). On a pass, the brief runs `swarm.sh review <slug> --head <reviewed sha> <url>`. Then, under merge = agent or when `swarm.sh grants <url>` grants merge, it runs `swarm.sh merge --head <sha> <url>` (reuse pin_rule and pinned_merge_rule, build.sh:229-267). Otherwise the review is the handoff and it stops. A moved head means `review-agent --next` and a review of the new head. The brief drops 'never merge'. Every swarm.sh call in the brief carries the project root (SWARM_PROJECT=<root>), since the agent runs in the story's worktree (build.sh:599-600). Keep the first line `Review <PR URL>, the PR of story <slug>, ...`, which review_brief_url reads. commands/swarm.md's lead backlog review arm (:147-168) then starts the review agent once and waits for it to merge or hand off. It no longer triages, tells findings or merges itself, so findings are not told twice and rounds not counted twice. Change only review_rule's read-only sentence (build.sh:56): conductor-hands-off rewrites review_rule after this epic. The docs change in this PR: bin/swarm.sh:49 and :36, docs/reference.md:1040 and :2375, docs/method.md's build step and README.md:43. Run the humanizer over that prose and commands/swarm.md. less-noise's brief-form story names this story and wording-fix-same-push in depends_on (all three edit review_brief).

**Done when:**
- tests/review_agent_test.sh: `swarm.sh review <slug> --head <old sha> <url>` with the PR head moved exits non-zero, names review-agent --next, and leaves the story's status unchanged; with the head matching, the story goes to review.
- The brief's final commands, run as written from a stand-in review pane against a fixture: under merge = agent they reach gh pr merge with --match-head-commit <sha>; under merge = human with no grant they leave the story in review with no merge call.
- Every swarm.sh call in the brief carries SWARM_PROJECT=<project root>, and its first line still matches review_brief_url; tests/no_agent_test.sh passes.
- commands/swarm.md's backlog review arm no longer tells findings or merges for a PR whose review agent is open; the swarm.md tests that pin it pass.
- The fallback reviewer's brief still says read-only (tests/fallback_reviewer_test.sh passes), and tests/doc_check_test.sh passes.

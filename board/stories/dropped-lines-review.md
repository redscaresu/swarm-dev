---
kind: code
status: blocked
epic: merge-safety
depends_on: [dropped-lines-command]
needs: [dropped-lines-command: the swarm.sh dropped-lines command, its arguments and exit codes, which the brief tells the review agent to run]
touches: [bin/lib/build.sh:dropped_lines_rule (new), bin/lib/build.sh:review_brief (the dropped_lines_rule call), tests/review_agent_test.sh:dropped-lines cases, tests/review_handoff_gaps_test.sh:dropped-lines no-review case, docs/reference.md:Building's review-round paragraph (the dropped-lines step)]
estimate_lines: 90
easy: true
---

# The review agent runs dropped-lines before it reads the diff, every round

From dropped-lines-command it uses `swarm.sh dropped-lines <owner/repo> <n> <head> <base>` and its exit codes (0 none, 1 lines, 2 cannot check). Add dropped_lines_rule to build.sh, in the style of the other *_rule helpers (merge_rule 21, guard_rule 37). Call it once in review_brief (1213), before the codex paragraph (1336). The rule says: before you read the diff, on this first round and after each review-agent --next, run `<sw> dropped-lines <owner/repo> <n> <the round's head> <base>`, filled from the PR URL ($2), the head ($5, or the head --next printed) and the base ($3). On exit 1, the printed lines are a finding to fix this round, whatever else the round finds: a regression this PR introduces, which review-rounds-end's round cap keeps. Send them to the builder with the round's findings. Once its fix lands, log it `log-finding --reviewer conductor --round <r> dropped-lines <PR URL> "<first line>"`, as finding_rule says. If the builder says in the PR that the drop is meant, merge's own check holds the PR for the user (dropped-lines-hold). On exit 2, write its line under the findings file's head lines, as for a skipped codex, and go on. review_at_head (build.sh:728-750) does not change: a die there reads as a failed start to no_review_events (lifecycle.sh:3144). Do not touch the brief's first line (review_brief_url, tests/review_agent_test.sh:824). Docs: the review-round paragraph in docs/reference.md § Building. An exit 2 (unchecked) from the check stops the round visibly: the review agent sends the builder the unchecked line and does not pass the PR. Under merge = human the handover names any drop the builder answered in the PR, so the user sees it before merging. The no-review case is a guard (it passes before and after this story), not a mutation proof.

**Done when:**
- tests/review_agent_test.sh dropped-lines cases: a round-1 brief carries the rule, with the PR's owner/repo, number, head and base filled in, before its codex paragraph. The rule names `--reviewer conductor` and the kind `dropped-lines`.
- The brief's first line is unchanged (the review_brief_url case at tests/review_agent_test.sh:824 passes).
- tests/review_handoff_gaps_test.sh dropped-lines case: events.tsv with an ok review-agent start, a log-finding dropped-lines row and an ok findings tell makes wait --lead print no no-review: line for the slug. The same fixture with that start refused prints one (the control).
- Copy-aside proof: removing the dropped_lines_rule call from review_brief turns the brief case red.
- shellcheck and tests/doc_check_test.sh pass.
- A round-2 review on --next's new pinned head runs the check against that head; dropping the check turns the test red.
- An unchecked result stops the review with a line to the builder; the PR does not pass.

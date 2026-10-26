---
status: draft
hld: 2026-10-25-swarm-dev-0-28
stage: v0.29.0
depends_on: [stage-gating, test-speed, clash-by-part, no-agent-alert, liveness-signals]
---

# Merge correctness gaps the 0.27 run left

Merge correctness gaps the 0.27 run left: under merge = agent a story PR that changes hooks/, .github/workflows/, the Makefile check target or .claude/ holds for the user instead of merging; merge_grant and pr_hld read the pinned head; release_check reads the base after the pin; the wait-pr stale-head race is reproduced and fixed or closed. HLD Risks and safety (protected paths), Design § Less work (Appendix D's unfiled gaps), Appendix C (wait-pr). risk: high.

**Done when:**
- Under merge = agent, swarm.sh merge holds for the user a story PR that changes hooks/, .github/workflows/, the Makefile check target or .claude/, with a `merge:` line in wait --lead naming the exit (the user merges, or lifts the hold), instead of merging it (today the regex at bin/lib/board.sh:867 is consulted only under merge = human, merge.sh:1275-1279; the one hold is costs: money, merge.sh:256); a test per path and one for a PR outside them; the v0.29.0 release PR lists it as a behaviour change every project gets.
- merge_grant and pr_hld read the pinned head, not headRefOid (board.sh:856-862), and release_check reads the base after the pin, not before the merge call; a test each.
- wait-pr after a push waits for the new head's check runs before reading green (Appendix C; bin/lib/merge.sh:950-1010 and WAIT_PR_GRACE at merge.sh:8): reproduced on current code first, then fixed with a test, or recorded in the story as already handled and closed.
- docs/reference.md's merge section documents the agent-mode hold and its exit; doc_check passes.

**Out of scope:**
The pattern at board.sh:867 (it already matches .github/, Makefile and .claude/: the gap is the agent-mode hold, not the regex); the contents-reader helper (less-noise); changing what counts as a grant; the four later stories (fixes-027).

**Constraints:**
- A PR touching hooks/, .github/ or .claude/ is itself a protected-path change: once the hold lands, such a story PR waits for the user.
- Order: this epic's pinned-head story goes after review-loop's merge_caller/merge_grant story (both edit bin/lib/merge.sh:merge_grant, merge.sh:122) and after less-noise's contents-reader story (merge_read, pr_hld, release_check).
- Nothing a board sets is removed; a removed key warns and loads (tests/removed_test.sh:30-48).
- tests/merge_test.sh, tests/merge_rules_test.sh and tests/merge_queue_test.sh (SLOW), tests/grants_test.sh, tests/wait_pr_test.sh (SLOW) pin today's paths.
- bash 3.2, shellcheck, loose_match_test, make test; humanizer over docs prose.

**Areas:** bin/lib/merge.sh:merge_hold, bin/lib/merge.sh:merge_grant and release_check, bin/lib/merge.sh:wait_pr, bin/lib/board.sh:pr_hld, bin/lib/lifecycle.sh:lead_queue merge line, docs/reference.md:merge holds, tests/ (merge, grants, wait_pr, wait_lead)

**Your part:**
User: once the hold is in, any later story PR that edits hooks/, .github/ or .claude/ waits on you. The cut is the release story's.

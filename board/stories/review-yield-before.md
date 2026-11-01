---
kind: lead
status: ready
epic: review-yield
depends_on: []
touches: []
estimate_lines: 70
easy: false
---

# Lead: record the v0.30.0 before numbers for the four kinds, and re-file review-yield-tuning as the post-release switch-on and after reading

Needs from demote-kinds-key: the key's name (demote_kinds), its value form and that it defers on rounds 1 and 2. Needs from reviewers-deferred-column: the deferred column the after reading uses. 1. Do not run flow over a past window live (AGENTS.md:178 keeps live reports to today). Take the v0.30.0 build's figures from the saved release reading (board/retros/v0.30.0.md and the release-v0-30-0 PR body), and record, in board/stories/review-yield-tuning.md under a new Before (v0.30.0 build) heading: the all <kind> rows for duplicate-code, missing-case, efficiency and hot-path-cost, the all all row, and review_loops' prs_4plus_rounds share, each with its window and population. 2. Rewrite review-yield-tuning in the same board PR: drop depends_on review-yield-baseline (no such file) for [demote-kinds-key, reviewers-deferred-column]; keep epic: review-yield and its after: review-yield line (a kind: lead after: story already does not hold its epic open, bin/lib/board.sh:100-114, 231-236); keep status later. Its steps: once swarm.sh version shows a release carrying demote-kinds-key, a PR adding demote_kinds = duplicate-code,missing-case,efficiency,hot-path-cost to .claude/swarm/config with the Before table in its body (**You:** merge it: .claude/ is a protected path); after one epic built wholly after that merge, flow --epic <e> once: per kind, the non-deferred decline rate, (declined - deferred) / (raised - deferred), escaped-of-deferred from the rounds totals, and the 4+ round share against the HLD's 15% bar (hld:128-130); keep the line if the sent decline rate fell and no deferred finding of those kinds proved real, else a revert PR (**You:** merge it). Remove its Codex budget section, pointing to commands/swarm.md:31-34, which already gives edit, hold and finish board PRs no codex-review. Land it with swarm.sh board-pr and swarm.sh merge --board. The plan narrows the epic: its Done when items 3 and 5 (the tuning PR, the after reading and the 4+ round bar) move to review-yield-tuning, and the review-yield command and the codex-time-limit and codex-bump-not-a-finding stories it names are not built. **You:** agree that narrowing, or say what to add back; the same board PR edits board/epics/review-yield.md's Done when to match. The after reading matches deferred and escaped rows by PR and exact finding text, filtered to the four tuned kinds; review_loops' totals span every kind (flow_review_loops.py:218). The rewrite replaces review-yield-tuning's old binding text and Done when, including 'nothing here waits on the user'.

**Done when:**
- On main, board/stories/review-yield-tuning.md has depends_on [demote-kinds-key, reviewers-deferred-column], epic: review-yield and after: review-yield, status later, and no reference to review-yield-baseline.
- It has a Before (v0.30.0 build) table with raised, fixed and declined for each of duplicate-code, missing-case, efficiency and hot-path-cost, the all all row and review_loops' prs_4plus_rounds share, each stating the flow command and window it came from.
- Its steps name the config line, the two **You:** merges and the after reading's keep-or-revert test, and its Codex budget section is gone with a pointer to commands/swarm.md.
- swarm.sh next run once after the merge prints no line naming review-yield-baseline.
- The user's answer on the narrowed Done when is recorded, and board/epics/review-yield.md matches it.
- review-yield-tuning on main says nothing of 'nothing here waits on the user', and its Done when is the new switch-on and measurement procedure.

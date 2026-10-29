---
kind: code
status: ready
epic: merge-safety
depends_on: []
touches: [bin/lib/board.sh:merge_rows, bin/lib/lifecycle.sh:lead_review_items, bin/lib/lifecycle.sh:lead_merge_shown, bin/lib/dash_render.py:needs-you merge rows, bin/lib/build.sh:conduct_merge_rule, tests/protected_hold_queue_test.sh:dropped-lines cases, tests/dash_needs_you_test.sh:dropped-lines row, docs/reference.md:review-item paragraph in The lead (dropped-lines holds), docs/dash.md:needs you merge rows]
estimate_lines: 130
easy: false
---

# status, dash, wait --lead and the conductor brief name a dropped-lines hold, not a protected path

dropped-lines-hold records its hold in the item's protected: entry with <what> `dropped base lines: <n>, first <file>: <text>` or `dropped base lines unchecked: <why>` (the format this plan fixes). Today every reader of those entries calls each one a protected path. Teach them that prefix, matched exactly (a `*...*` match needs its `# loose-match: ok` comment). merge_rows (board.sh:1757-1767) puts such PRs on their own row tagged ` (dropped base lines)`, apart from protected-path ones. lead_review_items (lifecycle.sh:2496-2512) tags those rows p, as it does `(protected path)`, with or without costs money. lead_merge_shown (2521-2535) prints `(held: dropped base lines: <n>, first <file>: <text>; exit: the builder restores them in a commit of its own, or the user reads the PR's answer and merges by hand)`, and for an unchecked one its why and the exit that the user checks the merge by hand. dash_render.py's row pattern (379) takes the new tag and keeps the row in needs you. conduct_merge_rule's sentence (build.sh:241) names the tag. Docs: the review-item paragraph in docs/reference.md § The lead (101-106) and docs/dash.md:121-122. The tests write the protected: state by hand, as tests/dash_needs_you_test.sh:344 does, so this story needs no merge change and builds beside dropped-lines-hold.

**Done when:**
- tests/protected_hold_queue_test.sh dropped-lines cases: with a protected: entry `<URL> <head> <epoch> dropped base lines: 2, first docs/x.md: row`, swarm.sh status prints `awaiting your merge (dropped base lines): <slug> <URL>`, and wait --lead prints its merge: line ending `(held: dropped base lines: 2, first docs/x.md: row; exit: the builder restores them in a commit of its own, or the user reads the PR's answer and merges by hand)`.
- A path entry on another PR of the same item still prints `(protected path)` with `changes <path>`. An unchecked entry prints its why and its own exit.
- tests/dash_needs_you_test.sh: the dropped-lines row stays in needs you under merge = agent.
- Copy-aside proof: removing the prefix arm from lead_merge_shown turns the wait --lead case red.
- The existing protected-path cases pass unchanged; tests/loose_match_test.sh and tests/doc_check_test.sh pass.

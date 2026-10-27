---
kind: code
status: blocked
epic: merge-holds
depends_on: [protected-path-hold, stuck-work-watch, concurrency-check]
needs: [protected-path-hold: merge_hold's protected-path arm in bin/lib/merge.sh and its `held: <slug> changes <path>` refusal, which this story records, stuck-work-watch: its new lines in bin/lib/lifecycle.sh:lead_queue and its docs/reference.md wait --lead lines, beside which the merge line's new form goes, concurrency-check: its idle lines in bin/lib/lifecycle.sh:lead_queue, which this story's lead_queue edit must keep]
touches: [bin/lib/merge.sh:merge_hold record, bin/lib/board.sh:waiting_on_user review arms, bin/lib/board.sh:costs_tag, bin/lib/board.sh:SET_FM_KEYS, bin/lib/lifecycle.sh:lead_review_items, bin/lib/lifecycle.sh:lead_heads, bin/lib/lifecycle.sh:lead_queue merge line, docs/reference.md:wait --lead lines, tests/protected_hold_queue_test.sh (new)]
estimate_lines: 200
easy: false
---

# wait --lead and status show a protected-path hold as the user's merge and name the exit

Uses protected-path-hold's merge_hold arm (bin/lib/merge.sh:merge_hold) and its `held: <slug> changes <path>` refusal. It builds on stuck-work-watch's and concurrency-check's lines in bin/lib/lifecycle.sh:lead_queue, and on stuck-work-watch's docs/reference.md wait --lead lines. Rebase on those before changing how the merge line is printed.
- When merge_hold holds a PR for a protected path, record it somewhere a file-only reader can see, keyed to that PR's URL. Two options: a state key set through set_fm and added to SET_FM_KEYS (board.sh:1606), or the `merge <slug> held:` events line. Pick one and say why in the PR.
- waiting_on_user's review arms (board.sh:1252, 1268) list held URLs on their own row, tagged ` (protected path)`. costs_tag's ` (costs money)` stays next to it. That row names only the held URLs. The story's other PRs keep their untagged row, as today. Today one row lists every URL on the item.
- Under merge = agent, lead_review_items (lifecycle.sh:2070-2084) passes the tagged row as it passes a costs: money one, with its own tag. lead_heads (lifecycle.sh:2092) treats it as held, so the PR is reported once.
- lead_queue prints `merge: <slug> <held PR URL> (held: changes <path>; exit: the user merges it)`. lead_heads reads every word after the slug as a PR URL, and LEAD_HEADS and LEAD_SEEN match whole lines. So the exit text is added only where lead_queue prints, and both files keep matching.
- lead_queue and waiting_on_user make no gh call (lead_queue's header says so). commands/swarm.md's `merge:` handler (:138), which tells the user the PR waits on their merge, stays as it is.
- docs/reference.md's wait --lead lines describe the new line.
- Order across epics: fixes-027's draft-epic-lead-row and plan-hld-gaps (in its draft plan) edit other arms of board.sh:waiting_on_user. If either is open alongside this one, this merges first: it changes only the two review-arm lines.

**Done when:**
- tests/protected_hold_queue_test.sh (new, merge = agent): one story lists two PRs, and swarm.sh merge holds only one of them because it changes hooks/x.sh (stubbed gh). `swarm.sh status` lists `awaiting your merge (protected path): <slug> <held URL>` with no other URL on that row. A wait --lead poll prints `merge: <slug> <held URL> (held: changes hooks/x.sh; exit: the user merges it)`, naming the held URL alone.
- Same file: a review story with no hold gets no merge: line under merge = agent, as today. When the story's prs: swaps the held PR for a new one, the old hold no longer tags it.
- Same file: the gh stub log shows no gh call from status or lead_queue. Only lead_heads' head reads call gh, and lead_heads reports the held PR once when a story and its epic both list it.
- tests/wait_lead_test.sh, tests/lead_queue_wait_test.sh and stuck-work-watch's and concurrency-check's tests pass.
- reference.md's wait --lead lines name the new line and its exit.

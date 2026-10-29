---
kind: code
status: blocked
epic: delivery-liveness
depends_on: [start-retry-review]
needs: [start-retry-review: the (try N of 3) events and their class, STARTS_PER_REVIEW, and review_agent's start loop (same part), which gains SWARM_START_TRY]
touches: [bin/lib/lifecycle.sh:no_review_line, bin/lib/lifecycle.sh:no_agent_lines review call, bin/lib/build.sh:review_agent first try, tests/wait_lead_test.sh:no-review cases, docs/reference.md:the no-review row, commands/swarm.md:the no-review paragraph, docs/reference.md:wait --lead command row, AGENTS.md:wait --lead bullet]
estimate_lines: 190
easy: false
risk: high
---

# wait --lead restarts a review agent whose start was cut short, within the budget

Needs from start-retry-review: the `(try N of 3)` review-agent events with their class, STARTS_PER_REVIEW, and review_agent's start loop. The command spends the whole budget itself, so this restart covers a review-agent command cut off partway through its loop, for example by a conductor's tool timeout (three starts can take minutes). no_review_line (lifecycle.sh:3213-3235) reads events.tsv for the slug. When the newest review-agent event since its last ok start ends `(try N of 3)` with N < 3 and the PR URL is known, it starts try N+1 and prints `no-review: <slug> <url> (started N+1 of 3), exit: <as today>`. Otherwise it prints as today. The restart runs only in wait --lead's poll: no_agent_lines passes its record flag on, a one-line change at lifecycle.sh:3450. next (board.sh:237), status (merge.sh:2906) and dash (board.sh:601-610) start nothing. The start runs `swarm.sh review-agent <slug> <url>` detached, with its output to a file under .swarm/lead. It never writes into lead_queue's $(...) (lifecycle.sh:3790), so the poll does not wait on it, and while the process runs it keeps the next poll quiet (no_agent_busy). review_agent's loop takes its first try number from SWARM_START_TRY and unsets it once read, as tell_agent does with SWARM_TELL_QUEUED, so the restart stays inside the budget. Docs: reference.md's no-review row and commands/swarm.md's no-review paragraph. Skeptic review (2026-10-29), which this scope follows. The budget is counted, not read from the newest line: over the review-agent events since the newest ok start, count the `(try N of 3)` lines plus a new `review-agent:restart <slug> started (try N of 3)` line the poll writes before it spawns; restart only while that count is below STARTS_PER_REVIEW (the command keeps its full 3; the poll uses only what a cut-off command left), and the last failure is in the retry class. A trailing `review-agent <slug> interrupted` (main_signal, bin/swarm.sh:1006) ends that try; an interrupt inside deliver_prompt (the brief may have gone) is an unclear start and is never restarted. Only wait --lead's poll restarts: next, status and dash call no_review_line too (board.sh:237, merge.sh:2906, board.sh:601-610) and stay read-only. The poll runs the restart detached, pinned to SWARM_PROJECT, with its output to a file, so lead_queue's captured stdout (lifecycle.sh:3790) neither sees it nor blocks on it. AGENTS.md's wait --lead bullet and docs/reference.md's wait --lead row say it now starts a review agent. Each try is logged when it starts, before deliver_prompt, as `review-agent:try <slug> (try N of 3) started`; an `interrupted` after a started try with no outcome counts that try as spent and unclear (the brief may have gone), so the poll never restarts it and the no-review line names the lead's check.

**Done when:**
- tests/wait_lead_test.sh no-review cases: when the newest review-agent event ends `(try 1 of 3)` and no review agent is live, one poll starts one review-agent on try 2 (the stub herdr log shows one agent start) and prints `(started 2 of 3)`.
- When the newest event ends `(try 3 of 3)`, the poll starts nothing and prints the line as today; a second poll after that also starts nothing.
- An out-of-class failure (no `(try` suffix): nothing is started and the line is as today.
- The same fixture read by `swarm.sh next`, `status` and `dash` starts nothing (the stub herdr log has no agent start).
- With no PR URL known, nothing is started and the gh pr list exit is as today.
- docs/reference.md's no-review row and commands/swarm.md's no-review paragraph describe `(started N of 3)`.
- A cut-off command (a fixture events.tsv ending in `review-agent <slug> interrupted` after `(try 1 of 3)`) makes the poll restart once, writing its restart line first; a second poll does not restart again.
- A restart killed before it logs an outcome still counts its try (the restart line), so the poll stops at 3 in all.
- next, status and dash never start an agent (each run against a no-review fixture leaves the stub herdr log with no agent start).
- The test waits for the detached child with a bound and reads its output file.
- A fixture where try 2 started and the command was then interrupted makes the poll start no agent and name the lead's check.

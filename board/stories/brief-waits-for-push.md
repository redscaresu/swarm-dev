---
kind: code
status: blocked
epic: review-follows-head
depends_on: [wait-past-head, brief-follows-moved-head]
needs: [wait-past-head (the --past flag of swarm.sh wait and its `pushed <sha>` line; which the brief's waits for a fix now run), brief-follows-moved-head (shares bin/lib/build.sh:review_brief and docs/reference-building.md:Review before closing; so it builds on that story's text)]
touches: [bin/lib/build.sh:review_brief builder waits (waits for a fix, guard_rule waits list), tests/review_agent_test.sh:f1 findings round block, tests/review_agent_test.sh:wait --stall brief check (283-284), docs/reference-building.md:Review before closing (builder waits), tests/guard_forms_test.sh:OWN_REVIEW, docs/reference-merging.md:review agent waits sentence (694-697), bin/lib/build.sh:review_brief --next refusal fallback wait]
estimate_lines: 150
easy: false
---

# After findings or a fix nudge, the review agent waits with wait --past for the builder's push

Needs from wait-past-head: `swarm.sh wait --past <sha> <slug>` and its `pushed <sha>` line. Needs from brief-follows-moved-head: the review_brief text that story rewrote (same function, same doc section). Today every wait on the builder is `wait --stall <slug>`, which ends only when the builder's turn ends (bin/lib/build.sh:1490-1494; docs/reference-building.md:846). Change each wait for a fix to `wait --stall --past <the head you reviewed> $1`. That means the wait after a findings tell (:1627), after a wording nudge, after a green-step nudge that asks for a fix, and the wait for the turn that has a queued tell (:1516). On `pushed <sha>`, the agent goes on at once: the green step on <sha> with wait-pr --head, then the diff, logging, and --next or --recheck as today. It reads the builder's pane for declines but does not wait for the turn to end; a finding neither fixed nor declined is not logged, as today. On idle or done with HEAD unchanged, the decline-only pass and the `no fix pushed` stop stay as they are. The wait before a findings tell stays a plain turn wait (wait --stall), since it keeps the tell from being queued. Add the --past form to the brief's guard_rule waits (:1481). Update tests/review_agent_test.sh's f1 block (597-650), whose brief_cmd now finds two wait forms, and its check at :283-284. Update docs/reference-building.md § Review before closing (:837-850). Convert the --next refusal's fallback wait that brief-follows-moved-head leaves as plain `wait --stall` too. The wait before a queued tell's delivery (build.sh:1497, 'wait for the builder as above, then for the delivery') stays a turn wait with no --past: a push before delivery would otherwise end it, and the queued findings would land on another head. tests/guard_forms_test.sh's OWN_REVIEW list (:74-76) must match the brief's forms exactly (:111): add the --past form there. docs/reference-merging.md:694-697 lists the review agent's waits: update it. Every wait for a builder's fix moves to --past, not only the after-findings wait: the wording nudge (build.sh:1516), the green step's fix nudge (:1546) and the wait after a queued tell is delivered (:1614). Only the wait before a queued tell's delivery stays a turn wait.

**Done when:**
- tests/review_agent_test.sh f1 block: the brief's after-findings wait is run from review-f1's pane with its head filled in, while f1's builder session stays busy. Once a commit in f1's worktree is gh's head, it ends with `pushed <sha>` and exit 0 before its timeout. With --past dropped from that brief sentence in a copy of the worktree, the same run times out; the PR pastes the FAIL line.
- The same command with no new commit ends with `idle` once done/f1 marks the builder finished, so the decline path still runs.
- In the flattened generated brief, the wait before a findings tell and the wait before a queued tell's delivery are still `wait --stall f1` with no --past, the --next refusal fallback uses --past, and guard_rule's list names the --past form; a has() check each.
- tests/guard_forms_test.sh passes with the --past form in OWN_REVIEW, and the generated --past command passes the guard.
- docs/reference-merging.md's review-agent waits sentence names the --past wait.
- docs/reference-building.md § Review before closing no longer says every wait on the builder is wait --stall. tests/doc_check_test.sh passes.
- Each of those fix waits, run from the review pane while the builder stays busy, ends with `pushed <sha>` once a commit is gh's head; a check each.

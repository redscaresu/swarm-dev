---
kind: code
status: blocked
epic: delivery-liveness
depends_on: [start-retry-review]
needs: [start-retry-review: start_retryable, STARTS_PER_REVIEW and the (try N of 3) event form]
touches: [bin/lib/build.sh:build_story start call, tests/env_allowlist_test.sh:story start retry cases, docs/reference.md:the story command row, docs/lead-by-hand.md:#688 entry]
estimate_lines: 150
easy: false
---

# swarm.sh story retries a start that ran nothing

Needs from start-retry-review: start_retryable, STARTS_PER_REVIEW and the `(try N of 3)` event form. build_story (build.sh:573-618) runs its start_agent call (612) in a subshell, in a loop of up to 3 starts with nap 3 between tries. It retries on the herdr texts start_retryable names, in the same process, reusing the worktree and brief it already made. A rerun of `swarm.sh story` stays refused by build_exists (596-600). Before the next try it closes the failed try's pane if one is left, as review_start_failed does (build.sh:1008-1011). A die inside the subshell does not write the command's outcome (swarm.sh die, DIE_LEVEL), so after the last try the loop dies again at the command level, with the failure ending `(try 3 of 3)`. Each retried failure logs one story event ending `(try N of 3)`. A failure where herdr may have sent the brief (deliver_prompt's unclear texts) is not retried. The escalate line and send_goal run once, after the start that worked. docs/lead-by-hand.md's #688 entry (38-43) is removed.

**Done when:**
- tests/env_allowlist_test.sh story start retry cases: a `swarm.sh story` whose first start fails with each herdr text (three cases) starts on try 2, exits 0, and logs one story event ending `(try 1 of 3)` and one `ok`.
- Three failures: exit 1, three starts, and story events ending `(try 1 of 3)`, `(try 2 of 3)` and `(try 3 of 3)`.
- Not retried: a start whose brief may have gone (an unclear deliver_prompt failure) makes one start; a second `swarm.sh story` on a started story dies once with `has a build already` and starts nothing.
- docs/reference.md's story command row states the retry; docs/lead-by-hand.md has no #688 entry.

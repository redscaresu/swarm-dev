---
kind: code
status: ready
epic: delivery-liveness
depends_on: []
touches: [bin/lib/build.sh:review_agent start loop, bin/lib/build.sh:start_retryable (new), bin/lib/build.sh:review_start_failed (the class), tests/review_handoff_gaps_test.sh:start retry cases, docs/reference.md:the review-agent command row, tests/review_agent_test.sh:unclear start case]
estimate_lines: 220
easy: false
---

# review-agent retries a start that ran nothing, up to three starts

Goal 4, the command half. Set STARTS_PER_REVIEW=3. review_agent (build.sh:633-682) runs its start (673-680) in a loop of up to 3 starts, with nap 3 between tries. It retries only when nothing runs and no agent can hold the brief. That means start_agent's stderr has one of herdr's texts: `pane ... not found` (pane_not_found), `the pane's shell did not take the agent's environment` (clean_env, agents.sh:498), or `agent_not_found` with nothing sent (deliver_prompt, agents.sh:932). It also covers review_start_failed's yes:none, yes:gone and yes:herdr: branch (build.sh:997). One helper, start_retryable <err> [state], holds that class so that build_story can use it too. review_start_failed dies (build.sh:1015), so it runs in a subshell on each try. Before each further try, the findings file and the stop note go aside again, as on the first. Unclear starts whose agent runs or cannot be read behave as today and are never retried (yes:busy, running, waiting, idle with the brief, auth, unlisted). Each retried failure logs one `record_event review-agent <slug>`: the failure line, naming its class and ending `(try N of 3)`. The last try's die ends `(try 3 of 3)` and becomes the command's own event (swarm.sh:1084-1086). Out-of-class failures log as today, with no suffix. no_review_events (lifecycle.sh:3144) matches by prefix, so it still reads the suffixed lines and is not edited. A start can now take three times as long, and the review-agent row says so. tests/review_agent_test.sh (SERIAL) pins an unclear review start (:410); that case keeps passing, since an unclear start (the brief may have gone) is never retried.

**Done when:**
- tests/review_handoff_gaps_test.sh start retry cases, one per herdr text (pane_not_found; the shell did not take the agent's environment; agent_not_found with nothing sent), in herdr's wording from docs/lead-by-hand.md:40-41: the first try fails, the second starts, and events.tsv has one review-agent event ending `(try 1 of 3)` and one `ok`.
- yes:none, yes:gone and yes:herdr: are each retried the same way (three cases).
- Three failures in a row: three starts, events ending `(try 1 of 3)` and `(try 2 of 3)`, the command's own event ending `(try 3 of 3)`, and the findings file back in place as today.
- Not retried: an unclear start whose agent reads idle with the brief, and one herdr cannot list, each make one start and log as today with no `(try` suffix.
- The existing review_start_failed cases (tests/review_handoff_gaps_test.sh:226-264) pass unchanged.
- docs/reference.md's review-agent command row states the retry and the budget.

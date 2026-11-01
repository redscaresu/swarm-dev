---
kind: code
status: ready
epic: reliable-runs
depends_on: []
touches: [bin/lib/agents.sh:clean_env, bin/lib/agents.sh:start_agent, tests/start_cold_shell_test.sh, docs/reference-building.md:agents' environment paragraph (§ Building), tests/env_allowlist_test.sh:one-pane cases (209-212, 254-257, 270-274), bin/lib/reports.sh:start_failures (start-retry count)]
estimate_lines: 160
easy: false
risk: high
---

# An agent start waits 60 s for a cold shell and retries once in a fresh pane (#688)

clean_env waits 30 s for the wrapper's ENV_READY marker (bin/lib/agents.sh:513) and dies on a miss. Story and review-agent starts already retry a marker miss up to 3 starts, each in a fresh pane (start_retryable, bin/lib/build.sh:816-838, from #732 and #746). Starts with no outer retry do not: a conductor's or planner's start through `swarm.sh agent`, and a step-up. Change: raise the wait to 60 s (a named constant; a SWARM_ override for tests only, no config key; keep --timeout for timeouts_test.sh). For starts with no outer retry only, a clean_env failure (marker miss or a failed `pane run`) closes that pane, prints one stderr line saying it retries in a fresh pane, logs a `start-retry` event (so flow's start_failures can count starts the retry saved, reports.sh:430), then runs next_pane and clean_env once more; a second failure dies as today. Story and review-agent starts keep their outer retry and get no inner one, so they never nest (at most 3 panes, as today). Mechanism: clean_env gets a mode that returns non-zero instead of dying, used only by start_agent's retry; restart_resume (lifecycle.sh:1135) and upgrade (lifecycle.sh:5280) still die. The agent_not_ready path's second clean_env call (agents.sh:686) does not retry. When the failed pane cannot be closed (clean_env's 'could not be closed: close it by hand', agents.sh:515), die at once with no second pane: it may still be open. Never call `herdr agent start` in a pane whose marker was not seen: this is the env-isolation path. tests/env_allowlist_test.sh pins today's one-pane behaviour at 209-212, 254-257 and 270-274: say in the PR which of those change and to what. The measured cold shell (14 s, HLD:500) is under today's 30 s, so the PR does not claim 60 s fixes it; the fresh pane is the fix. The PR says Refs #688, not Fixes: `pane ... not found` and agent_not_found on the brief send are not covered.

**Done when:**
- tests/start_cold_shell_test.sh: a herdr stub whose `pane wait-output` succeeds only when its --timeout is at least 45000 (a simulated 45 s cold shell) lets the start finish; with the wait put back to 30000 the test goes red (the PR shows that run).
- Same file: a stub whose first pane never shows the marker starts the agent in a second pane, the first pane is closed, and stderr names the retry; with the retry removed the test goes red.
- Same file: a stub that never shows the marker makes the start exit non-zero after exactly two panes, both closed, with no `herdr agent start` call in the stub's log.
- docs/reference-building.md's agents' environment paragraph states the 60 s wait and the one retry in a fresh pane.
- scripts/select-tests.sh --run passes and shellcheck is clean.
- A stub with a pane that cannot be closed and a marker miss opens exactly one pane and dies.
- A story start through build_story with a marker miss uses the outer retry only: no more panes than today.
- A retried start logs one start-retry event, and flow's start_failures counts it as saved.

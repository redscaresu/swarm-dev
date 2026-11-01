---
kind: code
status: blocked
epic: reliable-runs
depends_on: [codex-rate-limit]
needs: [codex-rate-limit (the rate-limit pattern beside CODEX_LIMIT_RE and its incident/fallback branch in codex_review; which the retry runs before)]
touches: [bin/swarm.sh:codex_review (retry), tests/codex_retry_test.sh, docs/reference-building.md:codex-review paragraph (§ Building)]
estimate_lines: 130
easy: false
---

# codex-review retries codex once after a rate limit, within codex_minutes

Needs from codex-rate-limit: the rate-limit pattern and its branch in codex_review that logs `codex-limit: rate limit` and runs the fallback. On a rate limit, codex_review (bin/swarm.sh:847) prints `codex rate limit: retrying in <N> s`, logs that as an incident with the codex-limit target and slug/role tail, waits CODEX_RETRY_SECONDS (60; SWARM_CODEX_RETRY_SECONDS for tests, no config key), then runs codex once more with the same args. All of it fits in the one codex_minutes budget: the time left shrinks by the first run and the wait, and the timeout still stops the second run. A second rate limit, or too little time for the wait plus FALLBACK_MIN_SECONDS, goes to the fallback or fallback_skip as today. A usage limit is not retried, since it resets in hours ('try again at <time>', tests/fallback_reviewer_test.sh:33). The marker, tee, fifo and traps cover the second run. The briefs' 'do not run it again' stays true. The retry is logged as an event, not a second codex-limit incident, so one limit counts once in incidents. The usage-limit retry the epic and HLD:502 ask for is not built: the user decides that in reliable-runs-readings.

**Done when:**
- tests/codex_retry_test.sh: a codex stub that prints the rate-limit line on its first call and a review on its second makes codex-review exit 0 with the review, call codex twice and log one retry line in events.tsv; with the retry removed the test goes red.
- Same file: a stub that hits the rate limit on both calls is called exactly twice, then the fallback runs (or `codex skipped: rate limit (...)` prints with fallback_reviewer empty).
- Same file: a rate limit then a retry logs exactly one codex-limit incident for the round.
- Same file: a usage-limit stub is called once.
- Same file: with SWARM_CODEX_SECONDS under the retry wait, codex is called once and the run ends within SWARM_CODEX_SECONDS plus CODEX_GRACE.
- codex_test.sh and fallback_reviewer_test.sh pass unchanged.
- docs/reference-building.md's codex-review paragraph states the one retry, its wait, and that a usage limit is not retried.

---
status: active
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.31.0
depends_on: []
---

# reliable-runs

Agent starts, the GitHub API quota and codex hold up under load

HLD § v0.31.0 additions. In the v0.30.0 build about 7 agent starts failed and worked on a retry (#688), the hourly REST quota ran out 3 times and paused every agent for up to 15 minutes (wait-pr made 46% of the calls), and 5 review rounds skipped codex on a usage limit.

**Done when:**
- stage: v0.31.0
- #688: an agent start waits long enough for a cold login shell (measured 14 s against the 30 s marker wait today) and retries once more before failing; a test with a slow shell stub starts.
- PR and CI state is read once per poll and shared across waiters (or cached), so concurrent wait-pr and watch calls do not each hit GitHub; `flow gh_calls` shows the drop against the v0.30.0 build's 40,380 REST calls.
- A review whose codex call hits a usage or rate limit retries it after a wait (the attempt is logged), rather than skipping codex for that round.
- docs: the codex capacity note (a Foundry deployment's capacity is the user's change, not the swarm's).

**Out of scope:**
#699 (merge-mechanics); raising any cloud deployment's capacity (a user decision).

**Constraints:**
- stage: v0.31.0. From the HLD's v0.31.0 additions (decided 2026-10-31); /plan-epic scopes it.

**Areas:** bin/lib/agents.sh (start_agent, clean_env), bin/lib/merge.sh and lifecycle.sh (wait-pr, watch), bin/lib/build.sh (codex_review_cmd)

**Your part:**
- none

---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [events-outcome-helper, outcome-readers-agents]
needs: [events-outcome-helper: append_event key=value fields and the outcome()/fields() readers in bin/lib/events_outcome.py (telemetry-readers), outcome-readers-agents: orders the shared sign_held and login_incident; adds slug= and role= after they read outcomes through the helper]
touches: [bin/lib/agents.sh:agent_fields (new), bin/lib/agents.sh:pane_check (incident), bin/lib/agents.sh:sign_held (incident), bin/lib/agents.sh:wait_agent (stalled and wait-timeout incidents), bin/lib/agents.sh:login_incident, bin/lib/agents.sh:tell_deliver (stale-blocked incident), bin/lib/lifecycle.sh:close_agent (idle-no-pr incident), bin/lib/lifecycle.sh:pull_board_repo (incidents), bin/swarm.sh:codex_review (codex-limit and reap lines), scripts/test.sh:reap line, tests/incidents_test.sh:slug and role cases, tests/codex_test.sh:reap fields case, tests/test_file_timeout_test.sh:reap fields case, docs/reference-logs.md:incident sentence (Logs and outcomes), docs/reference-logs.md:reap sentence (Logs and outcomes), tests/tell_blocked_test.sh:stale-blocked line compare]
estimate_lines: 240
easy: false
---

# incident and reap lines carry slug= and role=

Builds on telemetry-readers' contract (append_event's key=value fields, its separator, bin/lib/events_outcome.py outcome() and fields()), merged before this epic starts (the epic's depends_on). One helper, agent_fields in bin/lib/agents.sh, prints slug=<slug> role=<role>: the slug the call site has, or from the agent name (review-/conduct- prefixes and -done<N> stripped) only when it is whole: agent_name cuts at 32 characters, and a cut name gives no slug=, never a wrong one (rules.md: exact records); role from .swarm/agents.tsv column 2 for that name, as tell_gone reads it (agents.sh:1858). A field it cannot know is absent, never empty. Every record_event incident site in bin/ passes it: pane_check (agents.sh:1207), sign_held (:1442), wait_agent's stalled and wait-timeout lines (:1637, :1655), login_incident (:1724), tell_deliver (:2559), close_agent's idle-no-pr (lifecycle.sh:601), pull_board_repo's pull-failed and key-dropped (:411, :451; target -, so a slug only where the line names one story), codex_review's codex-limit and reap (swarm.sh:862, :870; slug from SWARM_STORY). scripts/test.sh's reap line (:100-105) writes slug=<slug> role=builder when the run's branch is story/<slug> (the branch it already logs, :161-175), nothing otherwise, with the contract's separator. Existing tests that compare these lines' $5 exactly move to outcome().

**Done when:**
- agent_fields cases: review-<slug>, conduct-<epic>, a -done2 name, a name with no agents.tsv line (no role=), and a 32-character cut name (no slug=).
- End to end: close's idle-no-pr incident, codex-review's reap line under a 1-minute codex_minutes stub (tests/codex_test.sh) and login_incident each give the story's slug and the agent's role in fields(); pull_board_repo's pull-failed line has neither.
- tests/test_file_timeout_test.sh: a TIMEOUT on branch story/abc writes a reap line with slug=abc role=builder; on a non-story branch it has neither, and its outcome() is still `TIMEOUT after <n>s`.
- Every existing test over these lines passes (scripts/select-tests.sh --run, then CI's shards).
- Copy-aside proof: dropping agent_fields from close_agent's site turns its case red.
- docs/reference-logs.md's incident and reap sentences name slug= and role= and when each is absent.
- Each writer category (the common helper, agent incidents, codex reaps, test.sh reaps) has a field assertion, and the PR body quotes a mutation's FAIL line for each.

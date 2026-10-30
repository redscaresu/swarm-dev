---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [incident-slug-role, features-section-check, stall-inputs, review-event-fields, pr-lifecycle-events, wait-timeout-activity, telemetry-hooks]
needs: [incident-slug-role: scripts/test.sh's reap line with its fields, features-section-check: the last reader; version= lands after every reader and writer, as the epic requires]
touches: [bin/lib/agents.sh:append_event (version field), scripts/test.sh:reap line, tests/events_test.sh:version cases, tests/test_file_timeout_test.sh:reap version case, docs/reference-logs.md:audit log paragraph (Logs and outcomes)]
estimate_lines: 90
easy: false
---

# version= on every event append_event writes, and on test.sh's reap line

From incident-slug-role it uses scripts/test.sh's reap line with its slug=/role= fields. append_event (agents.sh:874-879) adds version=<the installed plugin's version> to every line, read once per process with plugin_version (swarm.sh:112) from ${SWARM_HOME}/.claude-plugin/plugin.json, as record_agent does (agents.sh:855); unreadable gives no version=, never an empty one. scripts/test.sh's reap line adds version= from the checkout's .claude-plugin/plugin.json. The hooks' version= is telemetry-hooks'. The epic wants this last; see contradictions for why no depends_on encodes that.

It lands last: after every reader and writer story of this epic. Every test that end-anchors an event line gets its compare moved to outcome().

**Done when:**
- tests/events_test.sh version cases: a logged command's line has version= equal to plugin.json's; with plugin.json unreadable the line has no version= and the command still succeeds.
- append_event called with a field writes that field and version= after the outcome, and outcome() is unchanged.
- tests/test_file_timeout_test.sh: the reap line carries version= beside slug= and role=.
- Every existing test passes (scripts/select-tests.sh --run, then CI's shards).
- Copy-aside proof: removing version from append_event turns the version case red.
- docs/reference-logs.md's audit log paragraph names version=.
- `grep -rn` for end-anchored event-line compares over tests/ lists none that a version= field breaks; the full suite passes in CI.

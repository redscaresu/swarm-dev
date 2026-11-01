---
kind: code
status: ready
epic: status-speed
depends_on: []
touches: [bin/lib/merge.sh:status_report (section timers), tests/status_section_times_test.sh (new), docs/running.md:status row (§ Watching a run, 69)]
estimate_lines: 90
easy: true
---

# status names each section's seconds on stderr when asked

No per-step timing exists for status: run-times.tsv logs only the total (bin/swarm.sh:721-742), and gh-calls.tsv has no status or next rows (the lead's gh is not the shim). With SWARM_REPORT_TIMES=1, status_report (bin/lib/merge.sh:3144) writes one `time: <section> <s.mmm>` line per section to stderr, in order: no-agent, agents, stacked, waiting, next, idle, then total. Use now_ms, the clock run_time_start uses. Unset, or any other value, prints nothing, so it ships off. stdout is unchanged. It is an env var for diagnosis, like SWARM_REPORT_SECONDS, and not a config key. The PR body quotes one run on this repo's board with its 1-minute load. Run it once, not in a loop. Any run on the real board sets SWARM_RUN_TIMED=1, so it adds no row to the real .swarm/run-times.tsv that the epic's goal reads (bin/swarm.sh:735-742).

**Done when:**
- tests/status_section_times_test.sh: with SWARM_REPORT_TIMES=1, status on a fixture board (outside herdr) writes one `time:` line to stderr per section, in the order no-agent, agents, stacked, waiting, next, idle, total, each matching `time: <section> [0-9]+\.[0-9]{3}`.
- Same file: with SWARM_REPORT_TIMES unset, and with it set to 0, stderr has no `time:` line, and stdout is byte-identical to the SWARM_REPORT_TIMES=1 run's.
- Same file: with one section's timer call removed (proved on a worktree copy), the test goes red.
- status_time_limit_test.sh and report_deadline_test.sh pass unchanged.
- docs/running.md's status row names SWARM_REPORT_TIMES=1 and what it prints.

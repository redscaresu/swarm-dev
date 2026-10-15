---
kind: code
status: ready
epic: training-export
depends_on: []
touches: [bin/swarm.sh:session_log, bin/swarm.sh:session_usage, bin/swarm.sh:REPORT_PY (a gzip-aware open), bin/swarm.sh:outcomes_report (slug_of), bin/swarm.sh:cost_report, tests/outcomes_test.sh, tests/cost_test.sh, docs/method.md (§ the session copy)]
risk: high
---

# Readers fall back to the gzip copy of a session log once Claude Code deletes the original

close keeps a gzip copy of each session log in .swarm/sessions/ (docs/method.md § the session copy), but session_log never reads it, and its callers open the path with plain open(). After Claude Code deletes logs (30 days), cost, outcomes and the export lose tokens, start and the worktree slug. Add an opt-in archive fallback: report readers (session_usage, outcomes' slug_of, cost, and the export through them) look for the live log first, then the copy archive_session writes under the project's .swarm/sessions/ (`<date>-<agent>-<session id>.jsonl.gz`, matched on the session id suffix), and read either through one gzip-aware text opener. The liveness readers (session_mtime for the stall rule, goal_entry, dash's agent state) never use the archive, since an archive says nothing about a live agent.

**Done when:**
- tests/outcomes_test.sh and tests/cost_test.sh: with only the .gz copy present, outcomes shows the same slug (a long worktree slug), tokens and cost as with the live log, and `cost` the same totals; the fixture archive is written by archive_session itself, not by hand; with both present the live log wins; with neither, the cells are empty and nothing fails.
- A stall or goal check for an agent whose only log is the archive reads it as no sign of life (a test pins session_mtime ignoring the archive).
- Reading never creates files or events.tsv lines (the test compares the .swarm tree before and after).
- The PR shows each check failing with the fallback removed.

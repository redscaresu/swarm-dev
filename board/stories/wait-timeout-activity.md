---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [incident-slug-role]
needs: [incident-slug-role: wait_agent's wait-timeout incident with agent_fields (bin/lib/agents.sh:wait_agent)]
touches: [bin/lib/agents.sh:stall_reads (new), bin/lib/agents.sh:wait_agent (wait-timeout incident), tests/incidents_test.sh:wait-timeout activity cases, docs/reference-logs.md:wait-timeout sentence (Logs and outcomes)]
estimate_lines: 150
easy: false
---

# a wait-timeout with no progress logs activity=, from one stall_reads helper

From incident-slug-role it uses wait_agent's wait-timeout incident line, which it gave agent_fields. New stall_reads <name> <target> in bin/lib/agents.sh prints bg=0|1 test=0|1 sign=0|1 from the reads agent_stalled makes (test_running, bg_running, sign_held; agents.sh:1390-1400); stall-inputs reuses it. The wait-timeout incident (agents.sh:1655) adds activity=<the reads that are 1, comma-joined, or none> only when the agent made no progress since the wait began: no new commit (story_work_time) and no session write (session_mtime), as agents.sh:1386 reads them. The reads run inside the wait-timeout branch only, never per poll. With progress, no activity= field.

**Done when:**
- tests/incidents_test.sh wait-timeout cases: no commit and no session write since the wait began, with a test run stubbed running, logs activity=test; with nothing running, activity=none.
- The same timeout after a commit made during the wait logs no activity= field.
- stall_reads cases: each of bg, test and sign is 1 with its read stubbed true and 0 otherwise.
- Copy-aside proof: skipping the progress check turns the after-a-commit case red.
- docs/reference-logs.md's wait-timeout sentence names activity= and when it is absent.
- A timeout case with a session write (an assistant or tool line) during the wait and no new commit logs no activity= field; a commit-only reading of progress fails it.

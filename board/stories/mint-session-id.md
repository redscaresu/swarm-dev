---
kind: code
status: blocked
blocked_by: [claude-stub]
epic: agent-state-from-the-session
depends_on: [claude-stub]
touches: [bin/swarm.sh:start_agent, bin/swarm.sh:record_agent, tests/review_test.sh (agent start block), tests/epic_test.sh (story start checks)]
---

# start_agent mints the session id, passes `--session-id` and records it before the brief

For a claude agent, mint a UUID with python3 once, before the try loop (bin/swarm.sh:464), so a retry reuses it. Pass `--session-id <uuid>` only in the claude branch (:478-481). Call record_agent after a successful start and before deliver_prompt (:499-500), passing the id. Codex agents log '-'. record_agent takes the session as an argument and drops session_for_pane (:522-528). session_for_pane stays for cost_report's lead (:676-684). agents.tsv stays at 7 columns.

**Done when:** Against the herdr stub, a claude agent's `agent start` carries `--session-id <uuid>`, and its agents.tsv line's 7th field is the same uuid. A start retried after a failed first try uses the same uuid. A codex start has no `--session-id`, and its line ends in '-'. A start whose brief is not taken up still leaves its line. Every line has 7 fields. Each new check is shown red on the old code.

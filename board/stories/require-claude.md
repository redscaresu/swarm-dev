---
kind: code
status: blocked
blocked_by: [session-reader-and-wait]
epic: agent-state-from-the-session
depends_on: [mint-session-id, session-reader-and-wait]
touches: [bin/swarm.sh:start_agent (one call), bin/swarm.sh:require_claude (new), tests/config_test.sh (require_claude block), README.md (Requirements)]
risk: high
---

# require_claude refuses an old Claude Code before a pane opens

Add require_claude and call it beside require_trusted (:460) for claude agents. It parses `claude --version` in the format the pin recorded and compares it with V (from the HLD's open question) in python3. If the version is below V, or `claude` is missing, it refuses before any pane opens, naming V and the installed version. Self-check: when HERDR_PANE_ID has a session (session_for_pane, as in :676-684), that session must be in the list from the reader's helper; otherwise refuse, saying the interactive listing is missing. From a plain shell with no session, only the version is checked. Add no dispatch arm. In this PR, README's Requirements section names V.

**Done when:** In config_test with the stub: a version below V makes `agent` and `story` refuse, naming V, and the herdr log has no `tab create` or `pane split`. At V, a caller session missing from the list is refused; present, the agent starts. With no caller session, V alone starts. With no `claude` on PATH, the start is refused. README Requirements names V. Each new test is shown red on the old code.

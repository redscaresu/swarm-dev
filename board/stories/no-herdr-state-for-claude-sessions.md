---
kind: code
status: ready
epic: agent-state-from-the-session
depends_on: [off-screen-nudge, status-and-dash-read-the-session, tell-watch-and-free-name-read-the-session]
touches: [tests/agent_state_test.sh (new)]
---

# Structural test: herdr's agent_status is read only where the epic allows

Add tests/agent_state_test.sh, run over ${SWARM} in events_test's awk idiom (tests/events_test.sh:124-150). It tracks the enclosing function and the PANES_PY string. Every agent_status read must sit in an allowlisted place: `.get("agent_status")`, `['agent_status']`, a call to agent_status, and agent_field ... agent_status. The allowlist is deliver_prompt, the definitions of agent_field and agent_status, the reader's herdr fallback helper, agent_state's fallback branch, and `agent_field ... agent_status any` name checks. Each entry carries a one-line reason in the test. The test also fails on any `herdr agent read ... |` pipeline.

**Done when:** The test passes on the epic's head and fails on the pre-epic bin/swarm.sh, as the PR shows. It also fails when an `a.get("agent_status")` is added to dash_render, or `agent_status x` to watch_prs; both are shown by temporary edits that are then restored. shellcheck passes.

**From review (binding; overrides the scope above where they differ):**
- Name tidy_panes (:2564) as an explicit allowlist entry with its reason. Drop the 'retired agents' allowance. agent_state's no-entry fallback is allowed only from the named fallback helper; any other caller that reaches herdr for a Claude session fails the test.
- Note from the wave-5 conductor: #73 added `read_state` (bin/swarm.sh), the bash helper for the herdr fallback, which the allowlist needs; #69 added `login_expired` to PANES_PY, which reads the transcript, not herdr.

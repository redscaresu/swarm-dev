---
status: active
hld: 2026-10-13-builders-use-claude-codes-goal-advisor-and-agent-view
---

# Every Claude session swarm.sh starts takes its state from `claude agents --json`, joined by a session id swarm.sh mints at launch (HLD Goal 1, Rollout 1)

**Done when:**
- A fixture where herdr says `done` and the session says `busy` reports the builder as working, run through each reader in turn: `wait`, the stall rule, `status`, `watch`, `dash` and `tell`. One with no entry for a recorded session reports it `gone`, never idle, and `wait` returns on `gone` at once.
- A reused name (two agents.tsv lines for one name, the older retired) reports the newest line's session.
- A structural test fails when herdr's agent_status is read anywhere but for codex agents, agents with no recorded session, the `any` name check and `deliver_prompt`'s taken-up gate (bin/swarm.sh:737-749).
- `ended_on_api_error` is gone (:758-762 and its callers :861, :880). An idle builder with no PR on story/<slug> (no pushed branch in epic mode) is nudged up to API_ERROR_NUDGES times, and one with a PR is not; a test shows both. `wait_conductor` does not nudge: an idle conductor with no report is waited on until the timeout, and commands/swarm.md:27 says so.
- `wait`'s own nudges are logged to the events log as `nudge <name>`, and `tell` takes a required kind (`findings | nudge | resume`, no default), so the runs before the goal epic give a goal-off nudge baseline.
- `dash` shows `waitingFor` for a waiting agent and `!` for `unknown` or `gone`.
- `require_claude` beside `require_trusted` (:460) refuses before a pane opens, naming the minimum version, when the installed Claude Code lacks the interactive listing or `--session-id`; from a plain shell with no session the version check alone applies.
- Every agents.tsv line has a session id; agents.tsv stays 7 columns (cost_report :690, dash :2162 and the fixtures read 7).
- plugin.json is bumped and released, and one infrafactory epic has run on it.

**Out of scope:** a setting for the state source (the HLD has none). Conductor finish detection (`wait_conductor` still waits on the report). Codex agents. `deliver_prompt`'s gate. Escalation, attempts, the goal. Background sessions.

**Constraints:** bash 3.2, JSON through python3 as PANES_PY/STALL_PY do. The join is the UUID passed as `--session-id` in start_agent (:478-481), recorded before the brief is sent; the reader takes the newest agents.tsv line for a name. `wait` keeps `herdr agent wait` as its wake-up in STALL_POLL_MS slices and returns only on `idle`, `waiting` or `gone`. The stall rule's signs of life are unchanged except `herdr shows working` becomes `the session reports busy`. free_agent_name reads the session for a Claude agent with a recorded id; tidy and retire stay. Stories in this order: a shared `claude` stub (answers `--version` and `agents --json` from a fixture; CI has no `claude`) and the version pin by experiment first, so the pin can wait on a lead step without blocking the rest; then minting and recording; then the reader and `wait`; then the other readers; then docs. Existing tests that fake herdr state (tests/epic_test.sh, dash_test.sh, review_test.sh, next_test.sh) move to the stub; each new test is shown red on the old code. commands/swarm.md, docs/method.md (§ Building, config table) and README Requirements change in the same PR as the behaviour. Bump plugin.json.

**Your part:** after the release, run one infrafactory epic on it and say go before fable-on-call starts (the attempt count needs a trusted state source). If pinning the minimum version needs older Claude Code builds installed, that install is yours; the story says so.

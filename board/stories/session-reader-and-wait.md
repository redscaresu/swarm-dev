---
kind: code
status: blocked
blocked_by: [mint-session-id]
epic: agent-state-from-the-session
depends_on: [mint-session-id]
touches: [bin/swarm.sh:PANES_PY (new reader only), bin/swarm.sh:session list helper (new), bin/swarm.sh:settle, bin/swarm.sh:wait_agent, bin/swarm.sh:wait_conductor, tests/epic_test.sh (wait block), tests/next_test.sh (conductor block), tests/dash_test.sh (wait/stall block), docs/method.md (config table stall_minutes; § Building wait paragraph), commands/swarm.md:26]
---

# A session-state reader; `wait` and its stall rule read the session

Add one `claude agents --json` call per command (a helper beside session_for_pane) and a reader in PANES_PY. The reader maps a name to the newest agents.tsv line for it, then to its sessionId, then to the list entry. It returns busy | idle | waiting (with waitingFor) | unknown (a missing field, or the list call failed) | gone (no entry for a recorded session). Agents that are codex, have no line, or have '-' fall back to herdr through one named helper, which the structural test allowlists. settle and wait_agent keep `herdr agent wait` as the wake-up in STALL_POLL_MS slices. After each wake and each slice they read the session, and return only on idle, waiting or gone. A Claude agent's herdr status is never parsed. While the state is unknown, wait keeps stepping and prints one stderr line. The stall rule's `working` becomes the session's busy; STALL_PY is unchanged. wait_conductor follows the new words. ended_on_api_error stays until the next story. In this PR, update docs/method.md (stall_minutes row :127, § Building's wait paragraph) and the vocabulary in commands/swarm.md:26.

**Done when:** Using the claude and herdr stubs: when herdr says `done` and the session says `busy`, `wait` keeps waiting until the fixture turns `idle`, and `wait --stall` reports the builder as stalled. A recorded session with no entry returns `gone` within one slice. A failed list call reads as unknown, never gone. With two agents.tsv lines for one name (the older retired), wait reads the newer line's session. A codex agent is still waited on through herdr. The wait block of epic_test, the conductor block of next_test (:125-181) and the wait/stall tests in dash_test (:323-362) are rewritten against the stub. Each new test is shown red on the old code.

**From review (binding; overrides the scope above where they differ):**
- In a wait, the list is read once per wake or slice, not once per command. When herdr wakes but the session is busy or unknown, sleep out the rest of the slice before the next herdr wait (no busy-spin).
- A herdr wait that fails with an error other than a timeout also triggers a session read, so a gone session is reported. `gone` is returned on the first read after a wake, not after a slice.
- At the timeout, wait prints the last session word and exits 1, as today. A bare wait now polls in slices; rewrite dash_test.sh:337 to say so.
- Done when adds: with herdr's `agent wait` stub returning `done` at once and the session `busy`, a 3-slice wait makes at most 4 `claude agents` calls (the stub counts them) and exits 1 at the timeout; a gone session whose herdr wait errors prints `gone` and exits 0; the gone test runs with SWARM_STALL_POLL_MS set high so a one-slice delay fails.

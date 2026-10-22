---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [upgrade-ended-turn-is-idle]
touches: [bin/lib/agents.sh:tell_agent, tests/tell_note_test.sh (new)]
easy: true
estimate_lines: 70
---

# A note to a conductor whose turn has ended is sent as a prompt, not only left in its inbox

On 2026-10-22, the lead's notes to conduct-safer-faster-swarm sat unread for about 40 minutes. `tell <conductor> note` writes the note to .swarm/inbox/, and a conductor reads its inbox only when one of its own waits returns. This conductor's turn had ended at its prompt while its background waits ran for a long time. So "start gh-calls-by-agent first" and three newly ready stories went unread, until the lead sent the conductor a prompt by hand with `herdr agent prompt`. board-merge-tells-conductor and start-conductors-for-ready-work depend on these notes arriving.

Needs upgrade-ended-turn-is-idle's check that a busy session's turn has ended. tell_agent (bin/lib/agents.sh:1252) still writes the inbox file for `note`. Then, when the conductor's turn has ended (idle, or busy only with background jobs), it also sends a short prompt: "read your inbox now, act on it, delete it, then go back to your waits". It sends it with deliver_prompt and returns at once. A conductor mid-turn is left to read the inbox when its wait returns, as now. At most one prompt per conductor a minute, so a burst of notes wakes it once.

**Done when:**
- tests/tell_note_test.sh (new), with stub herdr and claude: a note to a conductor whose turn has ended writes the inbox file and sends one prompt. A note to one mid-turn writes the file and sends no prompt. Two notes within a minute send one prompt.

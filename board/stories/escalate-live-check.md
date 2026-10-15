---
kind: lead
status: blocked
blocked_by: [fable-failure-goes-to-you, conductor-give-up-rule, ladder-agent-counts]
epic: fable-on-call
depends_on: [fable-failure-goes-to-you, conductor-give-up-rule, ladder-agent-counts]
touches: []
---

# Start one escalate agent for real, answer Fable's consent dialog, and record its waitingFor and ladder line

Before the release, from this repo's main checkout (bin/swarm.sh from main, not the installed plugin), in herdr: the lead starts one escalate agent in this repo with a one-line brief (reply 'ready', change nothing): `swarm.sh agent fable-check fable-check "$PWD" escalate <brief>`. While it waits, the lead saves its `claude agents --json` entry (HLD:447: no waitingFor was ever captured). The lead accepts Fable's usage-credits consent in its pane, if one appears, with `herdr pane send-keys`, and records the keys that worked. The lead posts the `dash --ladder` escalate line, then `swarm.sh close fable-check` (no story file, so nothing counts). If waitingFor is not `dialog open`, the lead files a story fixing the conductor text and README before the release. If the keys the conductor text names do not accept the dialog, the lead files a story fixing them before the release. No **You:** step: by the user's decision of 2026-10-15, the lead decides escalation.

**Done when:**
- The captured agents --json entry, or 'no dialog appeared', is recorded on this story.
- dash --ladder's escalate line, with a count of at least 1 and the model the session's first message names, is recorded here.
- If waitingFor was not `dialog open`, a fix story exists and fable-on-call-release depends on it.

## Result (2026-10-15, lead)

The lead started `swarm.sh agent fable-check fable-check "$PWD" escalate <brief>` from main at 45d8bc0, in herdr. The pane shows `Fable 5.1 with xhigh effort · Claude Max`, and the agent replied `ready` after 2s.

- **No dialog appeared.** On this account (Claude Max), Fable started without a usage-credits consent prompt, so no keys were sent and waitingFor was never `dialog open`. The `claude agents --json` entry, captured while the agent was idle:
  `{"pid": 57849, "cwd": ".../swarm-dev", "kind": "interactive", "startedAt": 1792038932864, "sessionId": "a314dec7-5975-43ff-89ff-c8193db29b3a", "name": "swarm-dev-fd", "status": "idle"}`
- **dash --ladder's escalate line:** `escalate   → fable · xhigh  1 fable`.
- **No fix story was filed.** The conductor text doesn't name any keys; it tells the conductor to read the dialog and pick keys that accept Fable's consent. The dialog's shape and the keys that answer it are still unverified, because this account never shows the dialog. An account that does show it would be the first to test that path.
- `swarm.sh close fable-check` ran. There is no story file for it, so nothing counted.

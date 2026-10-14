---
kind: lead
status: blocked
blocked_by: [fable-failure-goes-to-you, conductor-give-up-rule, ladder-agent-counts]
epic: fable-on-call
depends_on: [fable-failure-goes-to-you, conductor-give-up-rule, ladder-agent-counts]
touches: []
---

# Start one escalate agent for real, answer Fable's consent dialog, and record its waitingFor and ladder line

Before the release, from this repo's main checkout (bin/swarm.sh from main, not the installed plugin), in herdr: the lead starts one escalate agent in this repo with a one-line brief (reply 'ready', change nothing): `swarm.sh agent fable-check fable-check "$PWD" escalate <brief>`. While it waits, the lead saves its `claude agents --json` entry (HLD:447: no waitingFor was ever captured). **You:** answer Fable's usage-credits consent in its pane if it appears; accept, or dismiss to see the ladder show Opus. The lead posts the `dash --ladder` escalate line, then `swarm.sh close fable-check` (no story file, so nothing counts). If waitingFor is not `dialog open`, the lead files a story fixing the conductor text and README before the release. **You:** tell the lead when you have answered the dialog.

**Done when:**
- The captured agents --json entry, or 'no dialog appeared', is recorded on this story.
- dash --ladder's escalate line, with a count of at least 1 and the model the session's first message names, is recorded here.
- If waitingFor was not `dialog open`, a fix story exists and fable-on-call-release depends on it.

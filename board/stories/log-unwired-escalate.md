---
kind: lead
status: blocked
blocked_by: [wire-escalate-role]
epic: fable-on-call
depends_on: [wire-escalate-role]
touches: []
---

# Log the unwired escalate role as a doc-ahead-of-code finding

After wire-escalate-role merges, the lead runs `swarm.sh log-finding doc-ahead-of-code <its PR URL> "method :152 promised Fable after two failures since db657b7; nothing called escalate"`, the text as the epic gives it. No **You:** step.

**Done when:**
- .swarm/findings.tsv has one doc-ahead-of-code line carrying wire-escalate-role's PR URL, and events.tsv logs the log-finding ok.

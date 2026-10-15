---
kind: lead
status: blocked
blocked_by: [export-command, session-log-reads-archive]
epic: training-export
depends_on: [export-command, session-log-reads-archive]
touches: []
---

# Run export over swarm-dev and infrafactory, check the row counts against agents.tsv, and post them here

The epic's lead story. From each project's root run the checkout's `bash <swarm-dev>/bin/swarm.sh export --format jsonl` and `--format tsv` into the scratchpad (never committed, never uploaded). Read-only over .swarm logs and session .jsonl; gh only reads PRs. Count agents.tsv builder lines (7 fields, role in code code-risky code-sonnet docs chore verify escalate; 56 and 132 on 2026-10-15, bin/swarm.sh:282-285). Post on this story: per project, the builder-line count, the jsonl and tsv row counts, and rows with an empty started or pr. No the lead step.

**Done when:**
- For swarm-dev and infrafactory, jsonl row count == tsv row count (minus header) == agents.tsv builder lines, posted here with the date.
- Every jsonl line parses as JSON and every tsv row has the header's width.
- Three finding texts sampled from each project's findings.tsv appear in neither file (grep -F).
- A mismatch or leak becomes a code story on this epic before the release story starts.

**From review (binding; overrides the scope above where they differ):**
- Depends on session-log-reads-archive; reports how many rows had their session from the archive.

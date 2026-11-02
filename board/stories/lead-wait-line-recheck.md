---
kind: code
status: blocked
epic: board-loose-ends
depends_on: [lead-wait-merge-reread]
needs: [lead-wait-merge-reread (lead_wake's merged-story drop; which shares the lead_wake part and runs before this recheck)]
touches: [bin/lib/lifecycle.sh:lead_wake (print-time recheck), bin/lib/lifecycle.sh:line_holds (new), tests/wait_lead_test.sh:recheck cases (new block), docs/reference-lead.md:recheck sentence (§ The lead)]
estimate_lines: 200
easy: false
---

# wait --lead checks that a line about a missing agent still holds before printing it

Needs from lead-wait-merge-reread: lead_wake's merged-story drop; this recheck runs on the lines that drop leaves. In the v0.30.0 build, wait --lead said an agent was missing while it was working. `idle: events-outcome-helper is ready with no build` came while its builder worked (incident 2026-10-30T19:06:55Z). A `no-review:` line for #778 came while review-outcome-readers-dash was reviewing (21:55:59Z). Each producer reads the one herdr list taken at the poll's start (lead_agents, LEAD_AGENTS). Before lead_wake prints a new line that claims an agent is missing (no-agent:, no-review:, and idle: ... is ready with no build), read herdr's agent list once more. That is one read per poll, made only when such a line is new. Drop the line when that read lists the agent it names as missing: the builder for no-agent: and idle:, review-<slug> for no-review:. A dropped line is left out of what lead_wake saves to LEAD_SEEN (lifecycle.sh:4505), so a later poll prints it if it still holds then. A failed or timed-out read keeps the line: the lead still hears it, as today. Cover every line kind that makes this claim, not only the two seen (rules.md:11). The docs name the kinds. One sentence in docs/reference-lead.md § The lead. The recheck uses each producer's own liveness test, not a builder-only one: no-agent: is suppressed today when either the builder or the review agent is live (lifecycle.sh:4119), so the second read checks both, with the same long-name mapping and pane ownership the producer uses. Correction: the `idle: ... is ready with no build` producer does not read herdr; it checks worktrees, events and branches (bin/lib/touches_rows.py:140, 154). For that line the recheck is a new herdr read of the builder, described and tested on its own.

**Done when:**
- tests/wait_lead_test.sh recheck cases: a stub herdr whose first list lacks review-<slug> and whose second list has it gives a poll that prints no no-review: line, and .swarm/lead/seen does not hold that line.
- A no-agent: line whose second read lists only the review agent (not the builder) also prints no line, as the producer would on that read.
- The same holds for an idle: ... is ready with no build line when the builder is on the second list, and for a no-agent: line.
- With both reads lacking the agent, each line prints as today. With a second read that fails, it prints.
- A later poll where both reads lack the agent prints the line then.
- Removing the recheck (copy-aside proof) turns the first two cases red. tests/doc_check_test.sh, shellcheck and scripts/select-tests.sh --run pass.

---
kind: lead
status: later
epic: safer-faster-swarm
depends_on: [merge-queue]
---

# Turn on the merge queue for swarm-dev

**Parked (2026-10-25):** a repo setting nothing in 0.28 needs. Start it again by setting it `ready` after 0.28.

After merge-queue ships in a release, the lead adds a merge_queue rule to swarm-dev's main ruleset
(REST, grouping up to 5, the required checks as today), records it in docs/reference.md, and watches
the next five merges go through the queue. Measure merges per hour before and after (flow).

**Done when:**
- swarm-dev's main ruleset has the merge_queue rule, and five PRs have merged through it.
- The before and after merges-per-hour figures are in the PR or the epic.

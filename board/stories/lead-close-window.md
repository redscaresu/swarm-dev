---
kind: lead
status: blocked
epic: ship-gates
depends_on: [protected-go-paths, docs-gate-go, patch-gate-port]
needs: protected-go-paths, docs-gate-go and patch-gate-port (their merged PRs, checked for the epic's Done when)
touches: [board/stories:ship-gates costs check]
estimate_lines: 4
risk: high
---

# The user merges the three code PRs, each held for them by its costs: money line

Closes ship-gates. The user chose on 2026-11-19 to hold the three code PRs with `costs: money`
under `merge = agent`, not with a `merge = human` window, so the rest of the board keeps merging while
they are away. `merge = agent` came back in its own PR that day.

**You:** merge protected-go-paths', docs-gate-go's and patch-gate-port's PRs, each once
`swarm.sh merge` holds it for you (`held: <slug> costs money`).

1. Lead: check that each was held and then merged by the user. gh runs as the user's login for
   agents too, so mergedBy cannot tell them apart. Read .swarm/events.tsv for each PR's
   `costs money` hold, and for no agent's `merge <slug> ok`.
2. Lead: tell the user that go-module, port-inventory and port-checks can now be planned.

**Done when:**
- gh pr view shows the three story PRs merged
- .swarm/events.tsv shows each PR held for the user before it merged, and no merge of it by an agent

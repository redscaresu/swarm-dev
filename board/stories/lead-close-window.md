---
kind: lead
status: blocked
epic: ship-gates
depends_on: [lead-open-window, protected-go-paths, docs-gate-go, patch-gate-port]
needs: lead-open-window (the merge = human line in .claude/swarm/config, set back here); protected-go-paths, docs-gate-go and patch-gate-port (their merged PRs, checked for the epic's Done when)
touches: [.claude/swarm/config:merge]
estimate_lines: 4
risk: high
---

# The user merges the three code PRs, then merge = agent comes back

Closes the window lead-open-window opened. This story turns ready once the three story PRs have
merged.

**You:** merge protected-go-paths', docs-gate-go's and patch-gate-port's PRs, each once its review
agent hands it over under `merge = human` (HLD:297-299).

1. Lead: check that each was handed over and then merged by the user. gh runs as the user's login
   for agents too, so mergedBy cannot tell them apart. Read .swarm/events.tsv for the review agent's
   handover, and for no agent's `merge <slug> ok`.
2. Lead: open a PR that sets `merge = agent` back in .claude/swarm/config.

**You:** merge it. .claude/ is protected.

3. Lead: pull the main checkout and check that `swarm.sh config merge` prints `agent` there.
4. Lead: tell the user that go-module, port-inventory and port-checks can now be planned.

**Done when:**
- gh pr view shows the three story PRs merged
- .swarm/events.tsv shows each PR handed to the user by its review agent before it merged, and no
  merge of it by an agent
- `git show origin/main:.claude/swarm/config` has `merge = agent`, on a commit after the three
  merges, and `swarm.sh config merge` prints `agent` in the pulled main checkout

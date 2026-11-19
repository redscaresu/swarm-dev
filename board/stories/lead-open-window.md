---
kind: lead
status: ready
epic: ship-gates
depends_on: []
touches: [.claude/swarm/config:merge]
estimate_lines: 4
risk: high
---

# Hold every PR for the user with merge = human, before ship-gates' first build

Opens the window in which the user merges this epic's three code PRs. The installed version has no
other hold for bash files: with `merge = human` and no merge grant, `swarm.sh merge` refuses and the
review agent hands the PR over (bin/lib/merge.sh:415-417,457; .claude/swarm/config:6).

The last v0.31.x is already cut: v0.31.3 was published on 2026-11-19 at 20:44Z, with the
dropped-lines fix (#1021), at merge commit 06b35a6. The config PR below is a lead PR outside the
board, so once it merges, the patch gate counts a change that is no fix, and no patch ships until
v0.32.0 (bin/lib/board.sh:1586). That is expected.

1. Lead: check that the user's go on this epic's board PR names protected-go-paths, docs-gate-go
   and patch-gate-port (the carve-out, HLD:481-486). Without it, stop and ask.
2. Lead: check that the lead and the running agents are on 0.31.3.
3. Lead: open a PR that sets `merge = human` in .claude/swarm/config, with a comment line naming
   ship-gates and the date.

**You:** merge that PR. .claude/ is a protected path, so `swarm.sh merge` holds it for you.

4. Lead: pull the main checkout and check that `swarm.sh config merge` prints `human` there before
   any of this epic's builds starts. swarm.sh reads the main checkout's config, not origin's
   (bin/swarm.sh:215), so a fetched but unpulled checkout still runs `merge = agent`.

Until lead-close-window, PRs of the other active epics and every board PR wait on the user too.

**Done when:**
- `swarm.sh version` in the lead's session prints 0.31.3
- `git show origin/main:.claude/swarm/config` has `merge = human`, on a commit after v0.31.3's
- `swarm.sh config merge`, run in the pulled main checkout, prints `human` before the first build
  of protected-go-paths, docs-gate-go or patch-gate-port starts
- The user's go on the board PR names all three code stories

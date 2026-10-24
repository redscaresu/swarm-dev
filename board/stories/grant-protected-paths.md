---
kind: code
status: ready
risk: high
depends_on: []
touches: [bin/lib/board.sh:pr_hld, tests/grants_test.sh, docs/reference.md:grants entry]
estimate_lines: 50
easy: true
---

# A merge grant never covers CI, the Makefile, hooks or Claude settings

`pr_hld` (bin/lib/board.sh, around :697) puts a PR under no grant when it touches `.claude/swarm/` or the board's `hld/`, so only the user takes those. A PR that changes `.github/workflows/`, the Makefile, `hooks/` or `.claude/settings.json` can still land under an HLD's `merge` grant, though each changes what checks a merge or what the agents may do. The hld-grants conductor left this policy call to the lead, and the lead takes the stricter one.

- `pr_hld` also returns no grant when the PR touches `.github/workflows/`, `Makefile`, `hooks/` or `.claude/settings.json`, in any repo it reads.
- One line on the protected paths in docs/reference.md's `grants` entry.

**Done when:**
- tests/grants_test.sh: a PR under an HLD that grants `merge` resolves to none when it touches each of those four paths, and still resolves to the HLD when it touches none of them.
- `make test` passes.

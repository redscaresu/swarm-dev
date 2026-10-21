---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/merge.sh:merge --release, commands/swarm.md:release, tests/]
---

# A release ships its docs

v0.22.0 and v0.23.0 shipped with release notes only: the guards, wait-pr, make test and the review
cap reached users with README, AGENTS.md and docs/ unchanged, although the release arm asks for a
newcomer docs review first (#221). The user asked (2026-10-21) that every release update AGENTS.md,
the README and any other docs as well as the release notes.

- `merge --release` refuses when `bin/`, `commands/` or `hooks/` changed since the last tag but none
  of README.md, AGENTS.md or docs/ did, naming the changed paths, unless the release PR body has a
  `Docs: none — <reason>` line.
- commands/swarm.md's release arm: before cutting `release/v<new>`, list the behaviour changes since
  the tag, land a docs PR that covers each (README, AGENTS.md, docs/reference.md, docs/method.md,
  commands/*.md as they apply, humanized), then bump the version. The release PR body names that
  docs PR.

**Done when:**
- A fixture repo with a bin/ change and no doc change since the tag makes `merge --release` refuse, naming the bin/ path; with a README change, or a `Docs: none — …` line, it proceeds.
- commands/swarm.md's release arm has the docs-PR step, and a test greps it.

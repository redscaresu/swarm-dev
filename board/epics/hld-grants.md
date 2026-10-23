---
status: active
parent: retro-and-shared-rules
depends_on: [hld-command]
check: make test
---

# An HLD's grants let the lead merge and release its work unasked, and nothing else does

The parent's goal 2, for the `merge` and `release` gates and the `stories` grant.

**Done when:**
- A function reads `grants:` from an HLD's front matter. An absent `grants:` means none. A value other than `epics`, `stories`, `merge` or `release` stops swarm.sh with the file and line, the way a bad config does (docs/method.md:118). It resolves the HLD for a story through its epic's `hld:`, or through a child epic's `parent:` up to an epic with `hld:`. A board PR resolves through the epics and stories its diff touches, and only when they all fall under one HLD. A release PR is covered when every story merged since the last `v` tag resolves to agreed HLDs that grant `release`. plan-hld uses this one reader for `grants:` and `hld:`.
- `merge_caller` (bin/lib/merge.sh:109-114) lets the lead merge a story PR or board PR under an HLD that grants `merge`, even under `merge = human`. `release_check` lets the lead run `merge --release` when an HLD granting `release` covers the release. Stub-gh tests check that each gate holds without the grant and opens with it. `costs: money` still holds the PR whatever the grant says, and the docs gate still applies to a release.
- With `stories` on the epic's HLD, commands/plan-epic.md writes the stories and opens the board PR without asking. Without it, the user approves, as today.

**Out of scope:** the `epics` grant (plan-hld and epic-guard), per-epic or per-story grants, any grant for cloud spend.
**Constraints:** the parent's. The guard hook's other refusals are untouched.
**Your part:** none.

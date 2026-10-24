# Epics

An epic is a goal bigger than one PR. It is scoped into stories (`docs/stories/`), each one PR,
and the epic is done when its **Done when** holds and its stories have merged; it then leaves the
board (`swarm.sh finish`). An epic in `review` waits for a human to merge the PRs on its `prs:`
line, and leaves the board once they have all merged. `check:` is optional: a command every
story's builder runs from its worktree, and makes pass, before opening its PR.
`/epic <title>` writes a new epic with you as `status: draft`, with the sections Problem (with
evidence), Goals (its **Done when**), Non-goals and Constraints; a reviewer attacks the draft, and
it becomes `active` only when you agree it. Nothing plans a draft epic.
`depends_on` lists the epics this one builds on (`[]` when none); `swarm.sh next` plans an
epic only once every epic it lists is done. A large epic `/plan-epic` splits into child epics, each
with `parent: <this-epic>` and its own **Done when**, and the parent becomes `status: split`: nothing
plans it, and it counts as done once none of its children is left on the board.

```
---
status: draft | active | later | review | split
depends_on: [other-epic]
parent: big-epic            # only on a child epic of a split one
check: make test
agreed: 2026-10-23         # set by /epic when the user agrees it
---

# <Goal, as a sentence>

**Done when:** how we will know the goal is met — observable, not "stories merged".
**Out of scope:** what this epic will not do.
**Constraints:** ADRs, safety rules and budgets that bound it.
**Your part:** the steps you or your own session will do (go-aheads, logins, hand steps), or none.
```

An epic goes `active` only with `agreed:`, a `parent:`, an `hld:` whose agreed HLD grants `epics`, or `lead_epics = on`.

A story joins an epic with `epic: <epic-file-name-without-.md>` in its front matter. Scope a new
epic with `/plan-epic <slug>` (swarm-dev `docs/reference.md` § Scoping an epic). In Obsidian,
`docs/Board.base` shows the board by status and by epic, and the epics themselves.

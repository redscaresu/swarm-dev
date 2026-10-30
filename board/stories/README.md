# Stories

Open work, one file per item. A file's front matter says whether it can be picked up:

    status: ready | blocked | later | review

`ready` stories are the queue. Each one other than a `lead` story is written to be handed to an agent as its brief:
what to change, and **Done when** — the acceptance. The PR that finishes a story deletes its
file; the PR is the record. A story in `review` has a PR that is green and reviewed and waits for
a human to merge it; its `prs:` line lists the PR URLs. List them with `grep -H '^status:' docs/stories/*.md`.

`kind` (code | docs | chore | lead) and `risk: high` choose who builds it
and with which model (swarm-dev `docs/reference-models.md` § Model and effort); `lead` stories are
never given to a swarm agent. A `lead` story says what it needs from you, and marks each step
that is yours with **You:** (swarm-dev `docs/method.md` § Who does what).

`attempts: <n>` is how many builds of the story failed. Only `swarm.sh close` writes it, when it
closes the builder of a code, docs or chore story that is still `ready` with no open PR, or when
`swarm.sh close <slug> --drop` clears a build whose PR is open (a bare close keeps that PR and puts
the story in review with it); once it reaches `escalate_after` (2 by default) the
story is built on Fable (swarm-dev `docs/reference-models.md` § Model and effort). `swarm.sh close <slug> <cause>`
says why the builder stopped (`met`, `impossible`, `stalled`, `bound`, `paused` or `cleared-on-error`;
with `goal` on, closing a `ready` story's builder needs one). `impossible`, `paused` and
`cleared-on-error` are not counted in `attempts:`, and while the story's PR is open they are refused
without `--drop`, since they hand the story on and close that PR.

When the builder says the **Done when** cannot be met (`impossible`), the story becomes `kind: lead`
with `escalated_from: <its kind>`, and a block with the lead's choices: re-scope the **Done when** and
run `swarm.sh reset <slug> <reason>`, or drop it. As with a failed Fable build, the lead decides,
so the block has no **You:** step.

When `swarm.sh close <slug> paused` or `cleared-on-error` closes a builder whose close would count
a failed build (a bare close when no PR is open; with an open PR it needs `--drop`, which closes it), the story is held the same way: `kind: lead`, `escalated_from: <its kind>`, `held_for: <cause>`, and a block with
the lead's choices, so no conductor or `/swarm-dev:swarm` run builds it again. `attempts:` stays as it was.
The lead drops it, or lifts the hold with `swarm.sh reset <slug> <reason>`, which puts the kind
back and removes `held_for:`, `escalated_from:` and the block but keeps `attempts:`. Lifting a hold
does not use up the story's one reset, and a later pause or error holds it again.

If the Fable build fails too, `swarm.sh close` turns the story into `kind: lead` with
`escalated_from: <its kind>` (`code (default)` when it had no `kind:` line), and appends a block
with the lead's choices and the attempts' PRs. The lead re-scopes it and runs
`swarm.sh reset <slug> <reason>`, which puts the kind back if it still says `kind: lead` and
removes `attempts:`, `escalated_from:` and the block, or drops it with `swarm.sh drop <slug> <reason>`,
which takes it off the board, and commits the change in a PR.

A story may belong to an epic (`epic: <slug>`, see `docs/epics/`) and list the files it
`touches`, which is how a wave avoids two agents editing the same file. A story whose work lands
in a sibling repo says so with `repo: <name>` (a sibling directory of this repo): its agent builds in a
worktree of `../<name>`, and the lead deletes the story file once that PR merges.

A `lead` story with an `after:` line naming its own epic (`epic: x`, `after: x`) waits until that
epic is built, such as a check on real cloud once the code is in. It does not count in its epic, so
an epic with only `after:` stories is still planned by `/plan-epic`. Once code stories were planned
for an active epic and none is open, it counts as done in `next`, `status` and `dash` while its
`after:` stories wait, so what depends on it goes ahead. On a board in the story's repo, the epic's
last code story's PR deletes the epic file without waiting for them. A list counts when it names
the story's own epic (`after: [x, y]`), and so do `after: [x]` and `after: x  # note`. An `after:`
that does not name its own epic is ignored, and a draft or later epic never counts as done this
way. "Planned" is read from the board and from its git history (an uncommitted deletion too); a
board not in git has no history, so there an active epic with only `after:` stories counts as done. The `after:` story stays on the board and is listed with the lead's other
stories.

`env: [NAME, ...]` names the environment variables a story's builder needs beyond the short list
every agent starts with (swarm-dev `docs/reference-building.md` § Building, The agents' environment). A story
holds names, never values: each value comes from the session that starts the agent, and the epic's
conductor gets the names too, so it can pass them on. The list goes on one line, in brackets. Each
name must match `[A-Z_][A-Z0-9_]*`, must be set in the session that starts the build, and must not be
reserved: one every agent gets already, the lead's own session's, or one that loads code. Otherwise
`swarm.sh story` and `conduct` refuse.

`estimate_lines: <n>` is the planner's guess at the PR's size in lines; a story is capped at one new
command or one changed behaviour and about 300 lines. `easy: true` marks a story under about 100 lines
that adds no new command and no shared helper in `bin/swarm.sh`.

A story that adds a test, lint rule, hook or review-prompt line for a kind of finding that keeps
recurring names it with `checks: <kind>`. Once it merges, `swarm.sh outcomes` shows how many PRs the
kind was fixed on in the 30 days before the merge and in the 30 days since.

Running several at once: swarm-dev `docs/reference-building.md` § Building. In Obsidian, `docs/` is
the vault and `docs/Board.base` is the board.

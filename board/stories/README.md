# Stories

Open work, one file per item. A file's front matter says whether it can be picked up:

    status: ready | blocked | later | review

`ready` stories are the queue. Each one other than a `lead` story is written to be handed to an agent as its brief:
what to change, and **Done when** — the acceptance. The PR that finishes a story deletes its
file; the PR is the record. A story in `review` has a PR that is green and reviewed and waits for
a human to merge it; its `prs:` line lists the PR URLs. List them with `grep -H '^status:' docs/stories/*.md`.

`kind` (code | docs | chore | lead) and `risk: high` choose who builds it
and with which model (swarm-dev `docs/reference.md` § Model and effort); `lead` stories are
never given to a swarm agent. A `lead` story says what it needs from you, and marks each step
that is yours with **You:** (swarm-dev `docs/method.md` § Who does what).

`attempts: <n>` is how many builds of the story failed. Only `swarm.sh close` writes it, when it
closes the builder of a code, docs or chore story that is still `ready`; once it reaches `escalate_after` (2 by default) the
story is built on Fable (swarm-dev `docs/reference.md` § Model and effort). `swarm.sh close <slug> <cause>`
says why the builder stopped (`met`, `impossible`, `stalled`, `bound`, `paused` or `cleared-on-error`;
with `goal` on, closing a `ready` story's builder needs one). `impossible`, `paused` and
`cleared-on-error` are not counted in `attempts:`.

When the builder says the **Done when** cannot be met (`impossible`), the story becomes `kind: lead`
with `escalated_from: <its kind>`, and a block with the lead's choices: re-scope the **Done when** and
run `swarm.sh reset <slug> <reason>`, or drop it. As with a failed Fable build, the lead decides,
so the block has no **You:** step.

When `swarm.sh close <slug> paused` or `cleared-on-error` closes a builder whose close would count
a failed build, the story is held the same way: `kind: lead`, `escalated_from: <its kind>`, `held_for: <cause>`, and a block with
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

A story that adds a test, lint rule, hook or review-prompt line for a kind of finding that keeps
recurring names it with `checks: <kind>`. Once it merges, `swarm.sh outcomes` shows how many PRs the
kind was fixed on in the 30 days before the merge and in the 30 days since.

Running several at once: swarm-dev `docs/reference.md` § Building. In Obsidian, `docs/` is
the vault and `docs/Board.base` is the board.

# Stories

Open work, one file per item. A file's front matter says whether it can be picked up:

    status: ready | blocked | later | review

`ready` stories are the queue, and each one is written to be handed to an agent as its brief:
what to change, and **Done when** — the acceptance. The PR that finishes a story deletes its
file; the PR is the record. A story in `review` has a PR that is green and reviewed and waits for
a human to merge it; its `prs:` line lists the PR URLs. List them with `grep -H '^status:' docs/stories/*.md`.

`kind` (code | docs | chore | verify | lead | operator) and `risk: high` choose who builds it
and with which model (swarm-dev `docs/method.md` § Model and effort); `lead` and `operator` stories are
never given to a swarm agent. A `lead` story says what it needs from you; an `operator` story's
**Done when** says what you do (swarm-dev `docs/method.md` § Who does what).

A story may belong to an epic (`epic: <slug>`, see `docs/epics/`) and list the files it
`touches`, which is how a wave avoids two agents editing the same file. A story whose work lands
in a sibling repo says so with `repo: <name>` (a sibling directory of this repo): its agent builds in a
worktree of `../<name>`, and the lead deletes the story file once that PR merges.

Running several at once: swarm-dev `docs/method.md` § Building. In Obsidian, `docs/` is
the vault and `docs/Board.base` is the board.

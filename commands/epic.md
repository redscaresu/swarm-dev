---
description: Use when asked to write, start or resume an epic. Starts or resumes a draft epic (docs/epics/) co-written with the user on the most capable model, in its own herdr pane
argument-hint: "[title]  e.g. Firewalled by default; none resumes the draft in progress"
---

The board is the directory `swarm.sh config board_dir` prints (`docs/` unless the project's
`.claude/swarm/config` says otherwise); every `docs/epics/` and `docs/stories/` below is inside it.

Start the epic `$ARGUMENTS`. Requires herdr (`HERDR_ENV=1`); if not inside herdr, say so and stop.

0. **No title given: pick up where things left off.** List the draft epics
   (`grep -l '^status: draft$' docs/epics/*.md`, never the README).
   - One draft: resume it (step 1, with its title from the file's `# ` heading).
   - Several: list them with their titles and ask which; do not guess.
   - None: there is no epic in progress. Run `swarm.sh _step` (next's step, which starts no conductor) and tell the user where the chain
     stands (for example "`conduct policy-correctness`: a ready story in an active epic") and that
     `/swarm-dev:swarm` continues it. Offer to start a new epic if they give a title. Then stop.

1. If `docs/epics/<argument>.md` exists, that file is the epic and its name is the slug (`next`
   names a draft by its file name, which may not be a clean slug). Otherwise make the slug from
   the title: lowercase it, turn every run of characters other than `a-z` and
   `0-9` into one `-`, and trim `-` from both ends (`Add rate-limiting (v2)!` is
   `add-rate-limiting-v2`). If the slug is empty or `backlog` (the name `conduct --backlog` uses),
   stop and ask the user for another title. The epic is then `docs/epics/<slug>.md` when that
   file exists, or else the one whose `# ` heading is this title. Whenever step 1 resolves to an
   existing file, by argument, by slug or by title, `<slug>` is its name without `.md`, whatever
   the title says now: an epic's title often differs from its file name. `<name>` below is
   `<slug>` made clean the same way (lower-cased, each run of characters other than `a-z` and
   `0-9` one `-`, `-` trimmed from both ends), since `board-pr` refuses any other name.
   `<name>` names the file, never the title: `board-pr open` tells an agreement PR by the epic
   its name matches, and the next paragraph looks for a branch of that name.

   First look for an agreement of this epic still waiting, which may have moved a new draft out of
   the main checkout (step 5): when the branch `board/agree-<name>` exists here or on origin
   (`git show-ref -q --verify refs/heads/board/agree-<name>`, `git ls-remote --exit-code origin
   refs/heads/board/agree-<name>`), read its PR (`gh pr list --head board/agree-<name> --state all
   --json state,url`). An open PR means the user agreed this epic and it waits on that PR: tell them
   so with its URL, and stop. A merged one: run `swarm.sh board-pr done agree-<name>` and
   `swarm.sh reconcile`, which pulls the agreed epic, and go on below, where it is live.
   A closed one: write the epic back from the branch first, as `status: draft` with no `agreed:` line, over
   any copy in the main checkout, since the branch holds the latest draft: run `git fetch origin
   board/agree-<name>`, then `git diff --name-only origin/<base>...origin/board/agree-<name>` names
   its path and `git show origin/board/agree-<name>:<path> > <path>` writes it. Then run `swarm.sh
   board-pr done agree-<name>` and go on below. No PR on the branch means step 5's `board-pr open`
   failed after the draft moved: the draft is in the worktree `<repo>-wt/_board-agree-<name>`, so
   finish step 5 from there (`board-pr open` again), or tell the user and stop. If `git ls-remote`
   cannot reach origin (with `--exit-code`, exit 2 only means no such branch), or `git fetch` or
   `gh pr list` fails, stop and tell the user; do not resume co-writing.

   If `docs/epics/<slug>.md` exists and is `status: draft`, resume it. If the epic exists with
   any other status, it is live
   (active, later, review or done) and not for co-writing: stop, say so with its status, and let
   the user pick another title. Otherwise create `docs/epics/<slug>.md` with this skeleton:

   ```
   ---
   status: draft
   depends_on: []
   ---

   # <title>

   ## Problem
   What is wrong today, with evidence (file:line, runs, incidents, numbers).

   ## Goals
   **Done when:** goals that could be checked and fail; plan-epic and the conductor read this line.

   ## Non-goals
   What this epic will not do.

   ## Constraints
   ADRs, safety rules, budgets and other epics that bound it.

   **Your part:** the steps the user or their own session will do, or none.
   ```

2. Write the co-author's brief to `.swarm/briefs/epic-<slug>.md`. `D` below is `.swarm/epic-<slug>`.

   > You are co-writing the epic in `docs/epics/<slug>.md` with the user, who is talking to you in
   > this pane and stays here from the first question to agreement. Read `AGENTS.md`, `STATUS.md`
   > if there is one, the project's ADRs and the code the epic touches before proposing anything.
   > Ask the user the questions that decide the epic, one or two at a time; do not invent
   > requirements. Fill in its four sections, Problem (with evidence: file:line, ADRs, runs),
   > Goals (each one checkable, under **Done when**), Non-goals and Constraints, and its **Your
   > part**. Keep it at the level of what and why; stories come later. Do not commit, do not touch
   > real cloud or credentials, and do not change `status`: the user agrees the epic, not you. When
   > the user says the draft is ready, `touch D/ready` and say the reviewer is starting; its
   > findings will arrive in this pane as a message, and you go through them with the user and
   > revise. When the user says they agree it, `touch D/agreed` and stop. Never create either file
   > unless the user said so.

3. `mkdir -p D` and remove any old `D/ready` and `D/agreed`, on a resume too: a leftover
   `D/ready` would start a reviewer at once, and a leftover `D/agreed` would set the epic active
   with no fresh agreement. Also delete any `agreed:` line from the epic's front matter: a stale
   ticket would let the epic go from draft to active later with no fresh agreement. Remove an old
   `D/review.md` when starting a new epic; on a resume, move it to `D/review-stale.md` and tell the co-author it is the last review, written against an
   earlier draft. Then `swarm.sh agent _epic epic-<slug> "$PWD" epic .swarm/briefs/epic-<slug>.md`
   (the tab `_epic`: a leading underscore no epic or story slug can take, so closing it never
   reaches another tab), and tell the user which pane to work in: they stay there throughout.
   This session supervises; it does not co-write.
4. In the background, without asking the user to come back, watch for `D/agreed` from step 3 on,
   whatever has or has not happened in this step: the user may agree without ever saying the
   draft is ready, or the reviewer may never write its file. The moment `D/agreed` exists, go to
   step 5. Meanwhile, wait until `D/ready` exists. Then
   write a reviewer brief (attack the draft, do not rewrite it: a problem with no evidence, goals
   that cannot be checked or could not fail, an epic that contradicts an ADR or a safety rule,
   non-goals that leave its edge unclear, risks not named, open questions that block planning it
   into stories; cite file:line; write findings only to `D/review.md`) and start it:
   `swarm.sh agent _epic epic-review-<slug> "$PWD" epic-review <brief>`. Wait until `D/review.md`
   is written, then `swarm.sh wait epic-<slug>` (tell refuses a busy co-author) and hand it over:
   write "The reviewer has finished: read D/review.md, summarise it for the user and go through it
   together." to a file and run `swarm.sh tell epic-<slug> nudge <file>`.
5. Once `D/agreed` exists, and only then, on the user's agreement, set
   `status: active`; nothing plans a draft epic. The same edit writes
   `agreed: <YYYY-MM-DD>` (today's date) into the front matter. When the board is in the project's
   repo, make that edit in a board PR named `agree-<name>`. Run `swarm.sh board-pr start
   agree-<name>`; the worktree it prints starts from origin's base. When the base lacks
   `docs/epics/<slug>.md` (a new draft), move the agreed file from the main checkout into the
   worktree with `mv`, so no copy is left to block the pull once the PR merges. When the base has
   it, copy it over the worktree's, then put the main checkout's copy back as the base has it (`git
   show origin/<base>:docs/epics/<slug>.md > docs/epics/<slug>.md`), since edits left there block
   the pull too. Make the edit in the worktree and commit it there (`git add -A`, then `git commit -S` with
   the brief's trailers: a moved draft is untracked until staged, and codex sees only committed
   changes), run one `swarm.sh codex-review` pass in the worktree and fix what it finds, then run
   `swarm.sh board-pr open agree-<name> "<title>" <body-file>`, which commits a fix, pushes and
   opens the PR (`board-pr open` again pushes a later fix). The pass comes before `open` because
   step 1 takes an open `agree-<name>` PR as reviewed: a session that stops between the two would
   otherwise leave a PR that merges unreviewed. A board outside the project's repo is edited where it is. Close the co-author and the reviewer (if it started) by name
   (`swarm.sh close epic-<slug>`, then `swarm.sh close epic-review-<slug>`; never `swarm.sh close
   epic`, which would close every tab whose label starts `epic-`), and tell the user the epic is agreed and
   that `/swarm-dev:swarm` plans it next (`/plan-epic <slug>`): once its board PR has merged, or at
   once on a board outside the project's repo. Once that PR has merged or closed, `swarm.sh board-pr
   done agree-<name>` removes its worktree and branch (step 1 runs it on the next `/epic` of this
   epic, or run it then).

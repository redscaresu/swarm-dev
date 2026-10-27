---
description: Use when asked to write, start or resume an HLD or a design. Starts or resumes a draft high-level design (docs/hld/) co-written with the user on the most capable model, in its own herdr pane
argument-hint: "[title]  e.g. Retros and shared rules; none resumes the draft in progress"
---

The board is the directory `swarm.sh config board_dir` prints (`docs/` unless the project's
`.claude/swarm/config` says otherwise); every `docs/hld/` below is inside it.

Start the HLD `$ARGUMENTS`. Requires herdr (`HERDR_ENV=1`); if not inside herdr, say so and stop.

0. **No title given: pick up where things left off.** List the draft HLDs
   (`grep -l '^status: draft$' docs/hld/*.md`, never the README).
   - One draft: resume it (step 1, with its file name without `.md` as the argument, never its
     `title:`, which the user may have edited since).
   - Several: list them with their titles and ask which; do not guess. Resume the one chosen by
     its file name, as above.
   - None: there is no HLD in progress. Run `swarm.sh _step` (next's step, which starts no conductor) and tell the user where the chain
     stands and that `/swarm-dev:swarm` continues it. Offer to start a new HLD if they give a title.
     Then stop.

1. If the argument contains `/`, stop and ask the user for a title: an HLD lives only in
   `docs/hld/`. If `docs/hld/<argument>.md` exists and is not the README (`README.md` in any
   case), that file is the HLD. Otherwise make a slug from the title: lowercase it, turn every run
   of characters other than `a-z` and `0-9` into one `-`, and trim `-` from both ends (`Add
   rate-limiting (v2)!` is `add-rate-limiting-v2`). If the slug is empty, stop and ask the user
   for another title.

   First look for an agreement of this HLD still waiting, which may have moved a new draft out of
   the main checkout (step 5): a branch here or on origin named `board/agree-YYYY-MM-DD-<slug>`,
   any date (`git branch --list 'board/agree-*'`, `git ls-remote origin 'refs/heads/board/agree-*'`;
   for an argument naming a file, `board/agree-` and that name made clean, as below). Its name
   after `board/` is the agreement PR's, `agree-<name>`. When there is one, read its PR (`gh pr
   list --head board/agree-<name> --state all --json state,url`). An open PR means the user agreed
   this HLD and it waits on that PR: tell them so with its URL, and stop. A merged one: run
   `swarm.sh board-pr done agree-<name>` and `swarm.sh reconcile`, which pulls the agreed HLD, and
   go on below, where it is agreed.
   A closed one: write the HLD back from the branch first, as `status: draft`, over
   any copy in the main checkout, since the branch holds the latest draft: run `git fetch origin
   board/agree-<name>`, then `git diff --name-only origin/<base>...origin/board/agree-<name>` names
   its path and `git show origin/board/agree-<name>:<path> > <path>` writes it. Then run `swarm.sh
   board-pr done agree-<name>` and go on below. No PR on the branch means step 5's `board-pr open`
   failed after the draft moved: the draft is in the worktree `<repo>-wt/_board-agree-<name>`, so
   finish step 5 from there (`board-pr open` again), or tell the user and stop. If `git ls-remote`
   cannot reach origin (with `--exit-code`, exit 2 only means no such branch), or `git fetch` or
   `gh pr list` fails, stop and tell the user; do not resume co-writing.

   The HLD is then the one whose name, without its leading `YYYY-MM-DD-`, is
   exactly that slug (`2026-10-23-add-cache.md` is `add-cache`, never `cache`), or else the one
   whose `title:` is this title. Whenever step 1 resolves to an existing file, by name or by
   title, `<file>` is its name without `.md` and `<slug>` is `<file>` without its leading
   `YYYY-MM-DD-`, whatever the title says now. `<name>` below is `<file>` made clean the same way
   (lower-cased, each run of characters other than `a-z` and `0-9` one `-`, `-` trimmed from both
   ends), since `board-pr` refuses any other name. If that file is `status: draft`, resume it. If
   that file has any other status (agreed or superseded), it is not for co-writing: stop, say so with its
   status, and let the user pick another title. Otherwise `<slug>` is the slug made from the
   title and `<file>` is `YYYY-MM-DD-<slug>`, dated today: create `docs/hld/<file>.md` from the
   skeleton in the fenced block of `${CLAUDE_PLUGIN_ROOT}/templates/docs/hld/README.md`: fill in
   `title:` and `date:` and the `# ` heading, set `status: draft`, keep `grants: []`, and write
   the ten section headings bare (`## Problem`, `## Goals`, ...), dropping the guide text after
   each heading in the skeleton.

2. Write the co-author's brief to `.swarm/briefs/hld-<slug>.md`. `D` below is `.swarm/hld-<slug>`.

   > You are co-writing the HLD in `docs/hld/<file>.md` with the user, who is talking to you in
   > this pane and stays here from the first question to agreement. Read `AGENTS.md`, `STATUS.md`
   > if there is one, the project's ADRs and the code the design touches before proposing anything.
   > Ask the user the questions that decide the design, one or two at a time; do not invent
   > requirements. Fill in its ten sections, Problem (with evidence: file:line, ADRs, runs) through
   > Epics, leaving Epics empty until epics are planned from it. Ask the user which `grants:` the
   > HLD carries (`epics`, `stories`, `merge`, `release`, or none) and what each one is for; write
   > only what the user names, and never fill `grants:` in by yourself. Keep it at the level of
   > what and why; epics and stories come later. Do not commit, do not touch real cloud or
   > credentials, and do not change `status`: the user agrees the HLD, not you. When the user says
   > the draft is ready, `touch D/ready` and say the reviewer is starting; its findings will arrive
   > in this pane as a message, and you go through them with the user and revise. When the user
   > says they agree it, `touch D/agreed` and stop. Never create either file unless the user said so.

3. `mkdir -p D` and remove any old `D/ready` and `D/agreed`, on a resume too: a leftover
   `D/ready` would start a reviewer at once, and a leftover `D/agreed` would set the HLD agreed
   with no fresh agreement. Remove an old `D/review.md` when starting a new HLD; on a resume, move
   it to `D/review-stale.md` and tell the co-author it is the last review, written against an
   earlier draft. Then `swarm.sh agent _hld hld-<slug> "$PWD" hld .swarm/briefs/hld-<slug>.md`
   (the tab `_hld`: a leading underscore no epic or story slug can take, so closing it never
   reaches another tab), and tell the user which pane to work in: they stay there throughout.
   This session supervises; it does not co-write.
4. In the background, without asking the user to come back, watch for `D/agreed` from step 3 on,
   whatever has or has not happened in this step: the user may agree without ever saying the
   draft is ready, or the reviewer may never write its file. The moment `D/agreed` exists, go to
   step 5. Meanwhile, wait until `D/ready` exists. Then
   write a reviewer brief (attack the draft in `docs/hld/<file>.md`, do not rewrite it: a problem with no evidence, goals
   that cannot be checked or could not fail, a design that contradicts an ADR or a safety rule,
   non-goals that leave its edge unclear, alternatives not weighed, risks not named, open
   questions that block planning it into epics, and its `grants:` as a risk: each grant hands
   agents a step the user takes today, so name what goes wrong if it is misused and whether the
   HLD needs it; cite file:line; write findings only to `D/review.md`) and start it:
   `swarm.sh agent _hld hld-review-<slug> "$PWD" hld-review <brief>`. Wait until `D/review.md`
   is written, then hand it over (a tell to a busy co-author is queued and delivered when its turn ends):
   write "The reviewer has finished: read D/review.md, summarise it for the user and go through it
   together." to a file `<note>` and run `swarm.sh tell hld-<slug> nudge <note>`.
5. Once `D/agreed` exists, and only then, on the user's agreement, set
   `status: agreed`; nothing plans epics from a draft HLD. When the board is in the project's repo,
   make that edit in a board PR named `agree-<name>`. Run `swarm.sh board-pr start agree-<name>`;
   the worktree it prints starts from origin's base. When the base lacks `docs/hld/<file>.md` (a
   new draft), move the agreed file from the main checkout into the worktree with `mv`, so no copy
   is left to block the pull once the PR merges. When the base has it, copy it over the worktree's,
   then put the main checkout's copy back as the base has it (`git show
   origin/<base>:docs/hld/<file>.md > docs/hld/<file>.md`), since edits left there block the pull too. Set the status in the worktree
   and stage it (`git add -A` there: a moved draft is untracked until then, and codex's
   `git diff <merge-base>` shows only tracked files), run one `swarm.sh codex-review` pass there
   and fix what it finds, then run `swarm.sh board-pr open agree-<name> "<title>" <body-file>`,
   which commits with the brief's trailers and signing and opens the PR (`board-pr open` again
   pushes a later fix). The pass comes before `open` because step 1 takes an open `agree-<name>`
   PR as reviewed: a session that stops between the two would otherwise leave a PR that merges
   unreviewed. A board outside the project's repo
   has no board PR: the HLD is agreed where it is, with no commit. Close the co-author and the reviewer (if it started) by name
   (`swarm.sh close hld-<slug>`, then `swarm.sh close hld-review-<slug>`; never `swarm.sh close
   hld`, which would close every tab whose label starts `hld-`), and tell the user the HLD is agreed
   and that `/swarm-dev:swarm` plans it into epics next: once its board PR has merged, or at once on
   a board outside the project's repo. Once that PR has merged or closed, `swarm.sh board-pr done
   agree-<name>` removes its worktree and branch (step 1 runs it on the next `/hld` of this HLD, or
   run it then).

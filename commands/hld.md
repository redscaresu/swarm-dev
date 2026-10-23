---
description: Use when asked to write, start or resume an HLD or a design. Starts or resumes a draft high-level design (docs/hld/) co-written with the user on the most capable model, in its own herdr pane
argument-hint: "[title]  e.g. Retros and shared rules; none resumes the draft in progress"
---

The board is the directory `swarm.sh config board_dir` prints (`docs/` unless the project's
`.claude/swarm/config` says otherwise); every `docs/hld/` below is inside it.

Start the HLD `$ARGUMENTS`. Requires herdr (`HERDR_ENV=1`); if not inside herdr, say so and stop.

0. **No title given: pick up where things left off.** List the draft HLDs
   (`grep -l '^status: draft$' docs/hld/*.md`, never the README).
   - One draft: resume it (step 1, with its title from the file's `title:`).
   - Several: list them with their titles and ask which; do not guess.
   - None: there is no HLD in progress. Run `swarm.sh _step` (next's step, which starts no conductor) and tell the user where the chain
     stands and that `/swarm-dev:swarm` continues it. Offer to start a new HLD if they give a title.
     Then stop.

1. If `docs/hld/<argument>.md` exists, that file is the HLD and its slug is its name without the
   leading `YYYY-MM-DD-`. Otherwise make the slug from the title: lowercase it, turn every run of
   characters other than `a-z` and `0-9` into one `-`, and trim `-` from both ends (`Add
   rate-limiting (v2)!` is `add-rate-limiting-v2`). If the slug is empty, stop and ask the user
   for another title. If an HLD whose name, without its leading `YYYY-MM-DD-`, is exactly `<slug>`
   exists (`2026-10-23-add-cache.md` is `add-cache`, never `cache`), or an HLD with this title does, and is
   `status: draft`, resume it. If it exists with any other status (agreed or superseded), it is
   not for co-writing: stop, say so with its status, and let the user pick another title.
   Otherwise create `docs/hld/YYYY-MM-DD-<slug>.md`, dated today, from the skeleton in the fenced
   block of `${CLAUDE_PLUGIN_ROOT}/templates/docs/hld/README.md`: fill in `title:` and `date:` and
   the `# ` heading, set `status: draft`, keep `grants: []` and the ten sections.

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
   write a reviewer brief (attack the draft, do not rewrite it: a problem with no evidence, goals
   that cannot be checked or could not fail, a design that contradicts an ADR or a safety rule,
   non-goals that leave its edge unclear, alternatives not weighed, risks not named, open
   questions that block planning it into epics, and its `grants:` as a risk: each grant hands
   agents a step the user takes today, so name what goes wrong if it is misused and whether the
   HLD needs it; cite file:line; write findings only to `D/review.md`) and start it:
   `swarm.sh agent _hld hld-review-<slug> "$PWD" hld-review <brief>`. Wait until `D/review.md`
   is written, then `swarm.sh wait hld-<slug>` (tell refuses a busy co-author) and hand it over:
   write "The reviewer has finished: read D/review.md, summarise it for the user and go through it
   together." to a file and run `swarm.sh tell hld-<slug> nudge <file>`.
5. Once `D/agreed` exists, and only then, on the user's agreement, set
   `status: agreed`; nothing plans epics from a draft HLD. Open a board PR for the HLD with one
   `swarm.sh codex-review` pass (a board outside the project's repo has no board PR: the HLD is
   agreed where it is, with no commit), close the co-author and the reviewer (if it started) by name
   (`swarm.sh close hld-<slug>`, then `swarm.sh close hld-review-<slug>`; never `swarm.sh close
   hld`, which would close every tab whose label starts `hld-`), and tell the user the HLD is agreed.

---
description: Start or resume a high-level design (docs/hld/) co-written with the user on the most capable model, in its own herdr pane
argument-hint: "[title]  e.g. Firewalled by default; none resumes the draft in progress"
---

The board is the directory `swarm.sh config board_dir` prints (`docs/` unless the project's
`.claude/swarm/config` says otherwise); every `docs/hld/`, `docs/epics/` and `docs/stories/` below
is inside it.

Start the HLD `$ARGUMENTS`. Requires herdr (`HERDR_ENV=1`); if not inside herdr, say so and stop.

0. **No title given: pick up where things left off.** List the draft HLDs
   (`grep -l '^status: draft$' docs/hld/*.md`, never the README).
   - One draft: resume it (step 1, with its title from the file's `title:`).
   - Several: list them with their titles and ask which; do not guess.
   - None: there is no design in progress. Run `swarm.sh next` and tell the user where the chain
     stands (for example "`conduct policy-correctness`: a ready story in an active epic") and that
     `/swarm` continues it. Offer to start a new design if they give a title. Then stop.

1. If an HLD with this title exists in `docs/hld/`, resume it. Otherwise create
   `docs/hld/<today>-<slug>.md` (today from `date +%F`; slug: lowercase, words joined by `-`) from
   the template in `docs/hld/README.md`, with `status: draft`, `title:` and `date:` filled in.
2. Write the co-author's brief to `.swarm/briefs/hld-<slug>.md`. `D` below is `.swarm/hld-<slug>`.

   > You are co-writing the high-level design in `docs/hld/<file>` with the user, who is talking
   > to you in this pane and stays here from the first question to agreement. Read `AGENTS.md`,
   > `STATUS.md` if there is one, the project's ADRs and the code the design touches before
   > proposing anything. Ask the user the questions that decide the design, one or two at a time;
   > do not invent requirements. Write the answers into the file section by section, citing
   > evidence (file:line, ADRs, runs). Keep the design at the level of what and why; stories come
   > later. Do not commit, do not touch real cloud or credentials, and do not change `status`: the
   > user agrees the HLD, not you. When the user says the draft is ready, `touch D/ready` and say
   > the reviewer is starting; its findings will arrive in this pane as a message, and you go
   > through them with the user and revise. When the user says they agree it, `touch D/agreed`
   > and stop. Never create either file unless the user said so.

3. `mkdir -p D`, remove any old `D/ready`, `D/agreed` and `D/review.md` when starting a new HLD, then
   `swarm.sh agent hld hld-<slug> "$PWD" hld .swarm/briefs/hld-<slug>.md`, and tell the user which
   pane to work in: they stay there throughout. This session supervises; it does not co-write.
4. In the background, without asking the user to come back: wait until `D/ready` exists. Then
   write a reviewer brief (attack the draft, do not rewrite it: goals that cannot be verified, a
   design that contradicts an ADR or a safety rule, missing alternatives, risks not named, open
   questions that block decomposition; cite file:line; write findings only to `D/review.md`) and
   start it: `swarm.sh agent hld hld-review-<slug> "$PWD" hld-review <brief>`. Wait until
   `D/review.md` is written, then hand it to the co-author:
   `t="$(swarm.sh _target hld-<slug>)" && herdr agent prompt "$t" "The reviewer has finished: read D/review.md, summarise it for the user and go through it together."`
5. Still in the background: wait until `D/agreed` exists. Then set `status: agreed`, open a PR for
   the HLD through the codex loop, `swarm.sh close hld`, and tell the user the design is agreed and
   that `/swarm` decomposes it next (`/plan-hld <file>`).

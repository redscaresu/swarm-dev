---
status: split
depends_on: []
check: make test
---

# The HLD layer comes back: a design agreed with the user says what the lead may do alone, and no epic goes active without that grant or the user

## Problem

- **The lead activated an epic the user had asked to plan together, and nothing stopped it.**
  On 2026-10-23 the lead wrote this file alone from the 0.26 retro and merged it with
  `status: active` (#399). The user had asked to plan 0.27 together. An active epic with no stories
  is what `next` offers to `/plan-epic` (bin/lib/board.sh:246), so the swarm would have planned a
  design the user never agreed. The lead set it back to draft by hand (#400) and parked the guard
  idea as a story (#402; its design is goal 4 below, and the PR that activates this epic deletes
  the story file). Today a board merge checks only that every changed path is on the board
  (bin/lib/merge.sh:190-204); it reads nothing about who agreed an epic.
- **There is no level above an epic any more, so there is nowhere to agree a release's design.**
  #259 replaced `/hld` with `/epic`, and #293 (2026-10-18) removed `/plan-hld`, the `hld-lead`
  role and the HLD template from the plugin (this board kept its own copy, board/hld/README.md).
  An epic is written with the user one at a time (commands/epic.md steps 1 to 5), and each one's
  stories are approved one at a time (commands/plan-epic.md:95-99). A release's worth of work,
  the 0.27 retro gate, the outer loop and memory extraction, has no single place where the user
  and the lead agree what it is and how much of it the lead may carry alone. The lead filled that
  gap by writing the epic itself, which is the first bullet.
- **The old HLD layer asked the user at every level, whatever the HLD said.** `/plan-hld` ended
  with "Ask before writing" (commands/plan-hld.md at 45b2af1a^) and every `/plan-epic` waits for
  the user's approval of its stories. The user wants the HLD itself to say what the lead may do
  unasked for the wave of work under it, so a trusted design runs through without a go-ahead per
  epic and per story, and an untrusted one keeps every gate.
- **Remnants of the layer are in the code and the board, and they disagree with each other.**
  `hld/` is a board-only path (bin/lib/merge.sh:690, docs/method.md:104,
  docs/reference.md:1355), `dash` walks `hld` (bin/lib/dash.sh:542) and board/Board.base lists
  it, the conductor's scope line says "leave the HLD ... alone" (bin/lib/build.sh:865), and
  board/hld/ holds an agreed HLD from 2026-10-13 whose `## Epics` links a deleted epic. Yet
  `next` has no arm for an HLD, nothing in bin/ reads `hld:` on an epic, and the plugin's
  `swarm.sh init` writes no `hld/`. A user who writes an HLD today gets a file the chain never
  picks up.

## Goals

**Done when:**

1. **An HLD can be written with the user and agreed.** `/hld <title>` (full name
   `/swarm-dev:hld`) creates `<board>/hld/YYYY-MM-DD-<slug>.md` as `status: draft` from a
   template with the old ten sections (Problem, Goals, Non-goals, Current state, Design,
   Alternatives, Risks and safety, Rollout, Open questions, Epics), opens a co-author pane on the
   most capable model, starts a reviewer when the user says it is ready, and sets `status: agreed`
   only when the user agrees it in that pane, the way `/epic` does for an epic. `/hld` with no
   title resumes the draft in progress. `swarm.sh init` writes `<board>/hld/README.md` with the
   template. Statuses are `draft`, `agreed` and `superseded`; `superseded` is written by hand, by
   the user, when a newer HLD replaces one. The roles `hld`, `hld-review` and `hld-lead` are back
   in `ROLE_GROUPS` (bin/swarm.sh:315) and `swarm.sh policy <role>` answers for them.
2. **An HLD's front matter grants the lead what it may do unasked under it, each permission on
   its own, and the plugin honours exactly that.** `grants:` is a list drawn from four values:
   - `epics`: `/plan-hld` writes the HLD's epics `status: active` without asking; without it, it
     proposes them and each goes active only when the user agrees it through `/epic`.
   - `stories`: `/plan-epic` writes each of its epics' stories without asking; without it, the
     user approves each epic's stories, as today.
   - `merge`: the lead merges the story PRs and the board PRs the HLD's work opens, under
     `merge = human` too; without it, the project's `merge` setting rules. `costs: money` holds
     whatever the grant says, and the guard hook's other refusals are untouched.
   - `release`: the lead runs `merge --release` on the release PR that ships the HLD's work,
     under `merge = human` too; without it, that PR waits on the user's merge.

   An absent `grants:` means none; a value outside the four stops swarm.sh with the file and line,
   as a bad config does (docs/method.md:118). The reviewer attacks the grants as a risk. The
   `merge` and `release` gates are code (`merge_caller`, bin/lib/merge.sh:109-114, and
   `release_check`), tested with a stub gh, one test per gate showing it holds without the grant
   and opens with it. The `epics` and `stories` gates are prompt text in commands/plan-hld.md and
   commands/plan-epic.md, and their check is observable on the board: with the grant, the board
   PR is open before any approval; without it, no board PR exists until the user has said yes.
   AGENTS.md's never-merge rule under `merge = human` and docs/method.md § Who does what name the
   `merge` and `release` grants as the exception.
3. **An agreed HLD is decomposed into epics by a swarm, and the chain carries on from there.**
   An HLD has epics when an `epics/*.md` on the board carries `hld: <its file name>`; the `## Epics`
   links are for people. `swarm.sh next` prints `plan-hld <hld>` for an agreed HLD with none, and
   `/swarm-dev:swarm` runs `/plan-hld <hld>`: survey, decompose, skeptics, codex and critic, as
   before #293. Each epic it writes carries `hld:`, the HLD's `## Epics` links it, and `next`
   plans each epic in turn. hooks/lead-stop.sh:181-188 enforces `plan-hld` as it does `plan-epic`,
   so the lead's turn cannot end with the HLD unplanned. When every epic with its `hld:` has left
   the board, the lead runs `swarm.sh finish <hld>`, which opens the board PR that deletes it;
   under `merge = human` the user merges that PR. This epic's own PR sets the 2026-10-13 HLD
   `superseded`, so the first `next` after the merge does not offer to decompose a finished design.
4. **No epic goes active without a ticket.** `swarm.sh merge --board` and `board-pr open` refuse a
   PR whose diff adds an `epics/*.md` as `status: active` or flips one from `draft` to `active`,
   unless the epic shows one of: an `agreed: <date>` line, which only `/epic` writes on the user's
   agreement; an `hld:` naming an agreed HLD that grants `epics`; a `parent:` (a child of a split
   epic, agreed through its parent); or the project's `lead_epics = on`. The refusal names the
   epic and says to run `/swarm-dev:epic <slug>`. A `later` to `active` flip passes: the user
   agreed that epic before parking it, and the docs tell them to flip it themselves. A PR that
   changes no epic's status is untouched. There is no `.swarm/` marker: `.swarm/` is untracked and
   `/epic` clears it on every resume. The guard reads the diff, not history, so an epic already
   active stays active. It stops a slip, as #399 was, not a lie: a lead can write `agreed:`
   itself. A board outside the repo has no board PR, so the rule there is the prompt text alone.
5. **The lead may still write its own epics for work no HLD covers, and the project decides
   whether it may activate them.** `lead_epics` (default `off`) in `.claude/swarm/config` is the
   one new key: `on` lets the lead set its own epic active and passes the guard in goal 4. Off, a
   lead-written epic stays `draft` until the user agrees it through `/epic`, and `next` lists it
   under waiting on you, as today (bin/lib/board.sh:624). commands/swarm.md and
   skills/swarm-dev/SKILL.md say the lead never sets an epic active without a grant, the key or
   the user.
6. **The docs describe the layer as it is.** docs/method.md § The planning chain has the HLD step
   at the top with its grants; docs/reference.md has a § Writing an HLD and a § Decomposing an HLD;
   README.md's quick start and AGENTS.md's three-step run name `/hld` where a release's worth of
   work starts; the flow diagram's source (docs/assets/swarm-flow.workflow.json) has the HLD step,
   and the light and dark PNGs the README embeds are re-rendered from it with archify by a
   `kind: lead` story with a **You:** step, since archify is on the user's machine, not in the
   repo. `tests/doc_check_test.sh` passes. The remnants in the Problem's last bullet are made real
   by this epic or removed.

## Non-goals

- The retro gate, the outer loop's fixed point, `refill`, load reaping and the shared rules from
  the lead's memory. 0.27 ships the layer; the retro and memory work follow as epics under the
  first HLD, written once this epic has merged. The appendix keeps the 0.26 evidence for it.
- A grant finer than the four: no per-epic or per-story grants, no grant for cloud spend
  (`costs: money` holds as it does today, whatever the HLD says).
- Migrating old epics: an epic already `active` on a board stays active. The guard reads diffs.
- Writing the first HLD. It is the step after this epic (**Your part**), not a goal of it.
- The Go migration and infrafactory's own changes. The guard is in the plugin, so it reaches
  every project on `claude plugin update`, infrafactory included; that is intended.

## Constraints

- Code that adds a flag or setting ships with it off, and a `lead` story turns it on
  (commands/plan-epic.md:77-79). `lead_epics` ships `off`. The guard in goal 4 is the one
  exception: it ships on, because the user asked that it hold in this release, and `lead_epics`
  is its off switch per project.
- `hld:` on an epic keeps the meaning board/hld/README.md:36-37 gives it; `parent:` keeps its
  meaning, and a child of a split epic under an HLD inherits the HLD's grants through its parent.
- `merge --release` keeps its docs gate (reference.md § Releases). A release the `release` grant
  lets the lead merge still needs the docs PR or the `Docs: none` line.
- Only the user changes an HLD's `status` and its `grants:`; `/hld` sets `agreed` on the user's
  word in the co-author's pane.
- `bin/swarm.sh` and `bin/lib/*.sh` stay bash 3.2; every GitHub Action pinned to a SHA; no change
  spends cloud money. `make test` stays green.
- All of this ships in 0.27. The PR that activates this epic deletes
  board/stories/epic-needs-agreement.md, whose design is goal 4.

**Your part:** agree this epic. Approve the stories `/plan-epic` proposes. Say go on the
`kind: lead` stories, and do the **You:** step of the one that re-renders the diagram with archify.
Once the layer has merged, run `/hld` for the 0.27 design and agree it, with its `grants:` filled
in by you; the appendix below is its starting material.

## Appendix: evidence for the first HLD, from the 0.26 retro (2026-10-22/23)

Written by the lead alone; kept here as the first HLD's starting material, not as this epic's
goals.

- **The board ran dry and nothing noticed.** With two agent stories left in review, the swarm sat
  nearly idle. `next` printed `wait conduct-...`. The rule "when the board runs dry, find the next
  work" existed only in the lead's private memory (written 2026-10-18), and the lead broke it. The
  user had to ask "why are there so few things running".
- **Follow-ups pile up unread.** Conductors logged about 100 findings as `declined out-of-scope`
  between v0.25.0 and the 0.26 release. Only the lead reading a backlog report by hand turned any
  of them into stories. Among them: swarm.sh never reaps a builder's leftover load (#376);
  `kill_tree` has a respawn race (#367); a note fires only from `merge --board`, not from
  reconcile or unblock (#360); `next` waits only on the first conductor (#365); three test stubs
  went vacuous after #374; `touches` misses files on #336, #344, #346 and #347.
- **Leftover load kept the machine busy.** In one day, builders left a 10-core stress container,
  three CPU spinners and four `yes` burners running for up to 3 hours. One builder sat stuck for
  3 hours waiting on its own burners. #376 added a brief rule and a test, nothing that reaps.
- **Lead-only rules.** The lead's memory holds about 40 feedback rules. Some are already in
  swarm-dev (red-merge guard, stall checks, user decisions not overridden, release docs gate).
  Others are generic and missing: refill when idle, fix the shared upstream cause first, a narrow
  sample is not a conclusion, verify against the thing itself, a silent fix looks like no fix.
- **The outer loop's collect step is the lead's, and there is no record it ran.** #290
  (2026-10-20) replaced lesson PRs with one `checks:` story per recurring finding kind, filed by
  `/swarm-dev:swarm` when a conductor finishes (docs/reference.md:1232-1234;
  hooks/lead-stop.sh:10 "collect is the lead's own step"). safer-faster-swarm's conductor wrote
  its report on 2026-10-23, and `.swarm/checks-filed.tsv` does not exist, which is consistent
  with either no recurring kind lacking a check or the lead never running collect. The first HLD
  should settle which, from `swarm.sh outcomes`' recurring block for v0.25.0..v0.26.0 and the
  `collect` lines in `.swarm/events.tsv`. Declined out-of-scope findings and the lead's memory
  were never in the loop either way.
- The user asked (2026-10-23) for a retro "just before the release of a version ... as part of
  swarm dev", and for memories that apply to all software swarm-dev builds to be extracted.

The lead's proposal for what the HLD's epics could hold, for the user to accept, cut or reshape
there: a `swarm.sh retro` that reports since the last tag (out-of-scope findings with no story,
red mains, flaky tests, stalls, leftover-process reaps, generic lead memories) and a
`merge --release` that refuses a release with no retro; the retro as the outer loop's fixed point
(recurring kinds, out-of-scope triage, memory step, whether or not a conductor collected); a
`refill` step in `next` and `status` when a conductor runs with at most one ready or building
story; the generic rules moved into swarm-dev where each is enforced, with
`swarm.sh rules --from-memory <dir>`; load reaping and a machine-wide CPU budget; and the
follow-ups listed above fixed or dropped with a reason.

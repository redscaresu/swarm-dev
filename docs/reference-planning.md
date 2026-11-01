# Reference: Planning

Part of [the reference](reference.md), which lists every section and the file that holds it.

## Writing an HLD

An HLD is a design for a release's worth of work, agreed with you before any epic is written. It
sits above the epic: HLD, then epics, then stories. It is optional; a single epic needs none.

1. **Start it.** In your Claude session, inside herdr: `/hld <title>`. This creates
   `<board>/hld/YYYY-MM-DD-<slug>.md` from the skeleton in the plugin's `templates/docs/hld/README.md`,
   not the board's copy of it, as `status: draft` with `grants: []`, and opens a pane (tab `_hld`)
   with a co-author on the `hld` role. `/hld` with no title resumes the one draft, asks which when
   there are several, and with none tells you where the chain stands.
2. **Write it in the co-author's pane.** It reads the code and the ADRs, then asks you the questions
   that decide the design and fills its sections, Problem through Open questions, and leaves Epics
   empty until epics are planned from it. It asks which `grants:` the HLD carries and writes only
   what you name. It reads the plugin's `rules.md` first, and runs the humanizer skill over the draft's
   prose after each revision, before it shows you the draft or asks you to agree it, never after you
   agree. If you agree a draft with no pass since its last revision, it runs the pass, shows you what
   changed and asks again. Without the skill it says so and goes on.
3. **Say it is ready.** A reviewer (the `hld-review` role) attacks the draft, its `grants:` included:
   each grant hands agents a step you take today, so it names what goes wrong if the grant is
   misused. Its findings arrive in the co-author's pane.
4. **Agree it.** Your session sets `status: agreed`, opens the board PR `agree-<hld>` with one codex pass, and
   closes the panes. Only you agree an HLD, and only you set `superseded`, by hand, when a newer
   one replaces it. Nothing plans a draft.

`grants:` is a one-line `[..]` list of `epics`, `stories`, `merge` and `release`. It is read only
from an `agreed` HLD, and any other value stops `swarm.sh` with the HLD's file and line.

| Grant | What the lead then does without asking you |
|---|---|
| `epics` | `/plan-hld` writes the HLD's epics `status: active` and opens the board PR without asking. Without it each epic is a draft that goes active only when you agree it through `/epic`. |
| `stories` | `/plan-epic` writes each of those epics' stories without your approval. |
| `merge` | Under `merge = human`, `swarm.sh merge` takes a story or board PR under the HLD (§ Merging). |
| `release` | Under `merge = human`, `swarm.sh merge --release` takes a release whose stories since the last tag are all under HLDs that grant it. |

`swarm.sh grants <story | epic | hld | PR URL>` prints the agreed HLD over an item and its grants.
A `costs: money` PR waits for you whatever the HLD grants. A PR that touches `.claude/`, `.github/`,
`hooks/` or a root `Makefile`, `GNUmakefile` or `makefile` (in any repo: each changes what checks a
merge or what the agents may do) is under no HLD, so no grant covers it, and so is one that touches
the board's `hld/`, except the plan PR in the shape § Decomposing an HLD gives (§ Commands).
A PR that touches `.claude/`, `.github/`, `hooks/` or a root makefile waits for you under either
merge mode: under `merge = agent`, `swarm.sh merge` holds a story PR that touches one, in any case
of letters, and you merge it by hand (§ Merging).
`lead_epics = on` (§ Settings) lets the lead set any epic active with no HLD at all; with it `off`,
the epic guard refuses an epic that goes active without an `agreed:` date, a `parent:`, or an `hld:`
whose HLD grants `epics` (§ The lead, § Merging). A draft epic that one of these lets go active
without your agreement (a `parent:` naming an epic that is active or split, an `hld:` naming an agreed
HLD that grants `epics`, or any draft with `lead_epics = on`) is the lead's: the gate, `status` and
`dash` list it as `draft epic: <slug>, the lead sets it active (<why>)`, not `run /epic <slug>`. A
draft with `stage:` is never the lead's this way, whatever its tickets: a stage `next` can open gives it
the staged path, and one it cannot open goes through `/epic` (**Staged epics**, § Writing an epic).

## Decomposing an HLD

`next` offers no `plan-hld` step for an agreed HLD whose file name holds anything but `a-z`, `0-9`
and `-`, or starts with `-`. `board-pr` refuses that name, so `/plan-hld` would fail only at its
end. The gate lists the HLD as `hld cannot be planned: <hld>, ...`; rename the file and every `hld:`
that names it. On a board inside the project's repo, `next` also skips an agreed HLD whose last
section is not `## Epics`. The HLD needs a line that is exactly `## Epics`, and after the last such
line only blank lines and lines `- [<slug>](../epics/<slug>.md)`, the same slug in both places and an
epic of that slug on the board. `/plan-hld` would plan any other HLD to the end, but `grants` puts
its plan PR under no grant, so it waits on a hand merge. The gate line names the form to use.

`swarm.sh next` names `plan-hld <hld>` for an agreed HLD with no `planned:` line, no epic carrying
its `hld:` and no plan worktree. On a board outside the project's repo, `/plan-hld` writes epics in
place with no PR, so an interrupted run leaves epics naming the HLD and no `planned:`. Before it
writes any epic, it writes `<project>/.swarm/<hld>/writing-epics`, one slug per epic it writes, and
it removes the file once `planned:` is set. `next` names `plan-hld <hld>` again while that file
lists every epic naming the HLD and no story's `epic:` or epic's `parent:` names one of them. The
rerun overwrites those epics. An epic the file does not list (an older or hand-written one), or one
that work has started on, leaves the HLD alone, and so does a board inside the repo. Work has started
once a story or child epic names the epic, or the project's `events.tsv` logs a conductor for it or
a `finish` of it. Until the rerun, `next` plans none of those epics. A run interrupted before
`writing-epics` existed stays stuck until you write the file by hand, one slug per epic naming the
HLD, after checking that none of those epics has work on it.
`/plan-hld <hld>` (the file name without `.md`) then:

1. Works on origin's copy of the board in `<repo>-wt/_board-plan-<hld>`, never the main checkout.
   It stops when a plan PR for the HLD is open, and when the HLD is not agreed, has a `planned:`
   value or already has epics naming it, except the epics of an interrupted run on a board outside
   the repo, as above. A leftover worktree from an interrupted run is resumed,
   or removed with `board-pr done` once its PR merged.
2. Runs a swarm: three surveys (`survey-code`, `survey-constraints`, `survey-overlaps`), one
   `hld-lead` that decomposes the HLD into epics (each independently shippable, with a **Done when**
   that could fail, its `areas`, and its **Your part**), a `skeptic-<slug>` per epic (at most five),
   one `codex` and one `critic`. Agents write JSON to `.swarm/<hld>/`, and a rerun reuses those newer
   than the worktree, or, on a board outside the repo, newer than the HLD file.
   Each agent's pane closes (`swarm.sh close <name>`) once its JSON has been read, never while only
   its `.partial` exists. A pane still working is left open, and the report names it.
3. Writes one `epics/<slug>.md` per epic with `hld: <hld>`, sets the HLD's `planned: <today>` and
   fills its `## Epics` section with one link per epic. It changes nothing else. Right after writing
   the epics, before the commit and codex pass (and on a board outside the repo, before the report),
   it runs the humanizer skill over their prose; without the skill the report says so.
4. Opens the board PR (`board-pr open plan-<hld>`) after one codex pass, with each epic `active`
   when the HLD grants `epics`; without that grant each epic is `draft`, and it asks you first.
   Findings are logged against the PR as in § Scoping an epic.

`swarm.sh grants` accepts that PR as under the HLD only in this shape: one `planned:` line set on an
HLD that is due a plan (on the board, an empty or missing `planned:` and no epic naming it), the HLD
changed after its last `## Epics` and nowhere else, at least one epic added, each a `draft` at the
PR's head unless the HLD grants `epics`, and nothing else touched. Under `merge = agent` the lead
lands it with `swarm.sh merge --board`, which reads no grant there; under `merge = human` it does so
only with `merge` granted, and otherwise you merge it. After the merge `next` offers `plan-epic` for
each active epic. Once every epic is built and gone from the board, `swarm.sh finish <hld>` deletes
the planned HLD in a board PR. It refuses a draft, a superseded HLD, one with no `planned:` and one
that still has epics.

## Writing an epic

Everything starts here, and it is the one stage you do by hand: the epic decides what every story
and line of code after it is for, so you write it with a co-author.

1. **Start it.** In your Claude session, inside herdr: `/epic <title>`, for example
   `/epic Add rate limiting to the API`. This creates `docs/epics/<slug>.md` with `status: draft`
   and opens a new pane (tab `epic`) with a co-author on the most capable model. Your session only
   supervises from here.
2. **Write it in the co-author's pane.** Switch to that pane and talk to it there. It reads the
   code, the ADRs and `AGENTS.md` first, then asks you the questions that decide the epic, one or
   two at a time, and writes your answers into the file section by section, citing evidence. It
   does not invent requirements, commit, or change `status`. It reads the plugin's `rules.md` first, and
   runs the humanizer skill over the draft's prose after each revision, before it shows you the
   draft or asks you to agree it, never after you agree. If you agree a draft with no pass since its
   last revision, it runs the pass, shows you what changed and asks again. Without the skill it says
   so and goes on.
3. **Say it is ready**, to the co-author, in the same pane. A reviewer (the `epic-review` role, the
   most capable model at `xhigh` effort) starts on its own and attacks the draft: a problem with no
   evidence, goals that cannot be checked, an epic that contradicts an ADR or a safety rule, unnamed
   risks, open questions that would block planning it into stories. Its findings arrive in the
   co-author's pane; go through them there and revise until you are satisfied. You never switch
   tabs.
4. **Agree it**, to the co-author. Your session, waiting in the background, sets `status: active`,
   opens the board PR `agree-<epic>` with one codex pass, and closes the co-author's pane. Only
   you can agree an epic; no agent changes its status, and `next` plans no draft epic.
5. **Hand over.** Run `/swarm-dev:swarm`. It sees an active epic with no stories and starts
   `/plan-epic`.

**What a good epic has.** Four sections: Problem (with evidence), Goals, Non-goals and
Constraints, and a **Your part** line. **Goals** are its **Done when**: checks that could fail,
because the conductor stops when they hold. **Non-goals** keep the plan from growing.

**Staged epics.** An epic in a staged HLD's Rollout carries `stage: v<x.y.0>`, the release that
ships it. This is an exception to step 4: a draft epic with both `stage:` and `hld:`, under an
HLD that grants `epics`, is set `active` by the lead, not by you through `/epic`, once the base has a
tag at or above the previous minor, `v<x.(y-1).0>`. A `v<x>.0.0` stage has no previous minor; its drafts go through `/epic`. A staged
draft with no `hld:`, or under an HLD without the `epics` grant, or on a board outside the project's
repo, still goes through `/epic`. Until
then, the gate, `status` and `dash` list it as `staged epic: <slug>, stage v<x.y.0>, after
v<x.(y-1).0>`, which needs nothing from you. See [Releases](reference-merging.md#releases) for the step that sets it
active and for when a stage's release is cut.

`board-pr open` and `swarm.sh merge` refuse a PR that sets an epic `active` before the base allows
its stage. They read `origin/<base>` and its tags, fetched first, and never the PR. The base
allows a stage when its newest `v<x.y.z>` tag is at or above the previous minor, or when an epic the
PR leaves alone is already `active` there at the same stage. An epic already `active` that the PR
moves to another stage is checked at the new one. A base with no tag counts as `v0.0.0`,
so a new project can start a `v0.1.0` epic. A `v<x>.0.0` stage needs a tag at or above the highest
`v<x-1>.y.z` stage on the base's board. An epic with no `stage:` is not checked, and one whose
`stage:` is not `v<x.y.z>` is refused. `board-pr open` and `merge --board` check whatever
`lead_epics` says; `merge` reads a story PR's epics only with `lead_epics` off, as it does for the
ticket. A fetch that fails refuses too, and so does one `merge` cuts off after `BASE_MOVED_WAIT`. The refusal names the epic, its stage, the newest tag and the
tag it waits for. To go on, commit the epic as `status: draft`. Under an HLD that grants `epics`,
`next`'s stage step sets it active once that tag exists, unless its stage is a `v<x>.0.0`. For that
stage, or with no such HLD, run `/swarm-dev:epic <slug>` again once the tag exists.

**Stopping and resuming.** The epic is a file, so nothing is lost if you stop: run `/epic` on its
own (or `/swarm-dev:swarm`, which sees the draft) and a new co-author picks up the draft in progress
from the file; if there are several, it asks which. With no draft at all, it tells you where the
chain stands instead.

## Scoping an epic

An epic (`docs/epics/<slug>.md`: goal, **Done when**, out of scope, constraints) becomes stories
with `/plan-epic <slug>`. An epic of at most 3 stories with no `risk: high` is planned by the lead
alone, with one codex pass over stories committed in a board-PR worktree. A large one (more than 8
stories, or goals that can ship apart) is split by the lead alone into child epics, each with
`parent: <epic>` and its own **Done when**, planned in turn; the parent becomes `status: split` and
counts as done once none of its children is left. Any other epic gets one survey agent unless its text names another repo (three
then), one lead decomposition into one-PR stories with `kind`, `touches` and `depends_on` (a
chain at most 3 stories deep, and a story's scope opens with what it needs from each `depends_on`),
a skeptic only on each `risk: high` story (capped at five, the rest logged), a codex pass and a critic, all in
parallel. `risk: high` goes only to real-cloud, teardown, credentials and safety paths. Agents write their answers to
`.swarm/<epic>/`. Each agent's pane closes (`swarm.sh close <name>`) once its answer has been read, never while
only its `.partial` exists; a pane still working is left open, and the report names it. The user sees refuted stories, contradictions, the risky stories and stories ÷
longest chain first, and approves before the board PR opens; review fixes are folded into
each story's scope. Once the board PR is open, each skeptic, codex and critic finding is logged
against it with `log-finding --reviewer <who>`, declined ones with `--declined <reason>` too. A full run is four agents (survey, lead, codex, critic) when no story is `risk: high`, plus up to five skeptics (including any added when review moves a story to `risk: high`) and, for a multi-repo epic, two more surveys, so
scope deliberately.

**Ship code switched off.** Code that adds a flag or setting merges with it off, so the merge
changes no behaviour; a separate `lead` story turns it on. Bundled, a failure cannot say whether
the code or the switch broke it, and the rollback has to undo both. Two exceptions:
`escalate_after` ships on, at `2`, by the user's decision of 2026-10-13. It changes nothing until a
story has failed twice. `codex_minutes` ships on, at `10`, because without a limit a codex review
can hang for good.

A story's **Done when** names what the builder's session can show (a test run, a command's output, a file), never something only the conductor or a merge can show, so a goal's judge can see it.

## Commands

| Command | What it does |
|---|---|
| `/epic <title>` | Write a draft epic with a co-author agent; it is planned once you agree it. |
| `swarm.sh grants <story \| epic \| hld \| PR URL>` | Print the agreed HLD over a story, epic or HLD and its grants, one per line, or `none`. A story goes to its `epic:`, then each `parent:`, up to the first epic with `hld:`; a draft or superseded HLD, a missing one, a missing epic, a story with no epic and a `parent:` cycle all give `none`. A name that is no story or epic but an HLD in the board's `hld/` is that HLD: an agreed one prints itself and its grants, any other gives `none`; a story or epic of the same name wins. A story PR is its stories' (their `prs:` lines); a board PR is the epics and stories it touches, each as the board has it and as the PR's head has it, and a PR that touches `.claude/`, `.github/`, `hooks/` or a root `Makefile`, `GNUmakefile` or `makefile` (in any repo, since each changes what checks a merge or what the agents may do) or the board's `hld/`, or a PR no story lists that touches anything but the board's epics and stories, gives `none`. /plan-hld's board PR is the exception: a PR that modifies one agreed HLD that is due a plan (no epic on the board names it, and its `planned:` value is empty once quotes, brackets and a trailing comment are gone), setting its single `planned: YYYY-MM-DD` line and changing it otherwise only after its last `## Epics` line, and adds at least one epic and changes nothing else, each epic under that HLD at the PR's head, is under that HLD, with the grants of the board's copy. The HLD's last section must be `## Epics`: after that line, both the board's copy and the PR's may hold only blank lines and list items whose whole content is one markdown link to an epic file in the board's `epics/`, or to one the PR adds, with the epic's slug as the link text. Without the `epics` grant each added epic must be a `draft` at the PR's head. Deleting the HLD, or any other change to it, gives `none`. Items under two HLDs give `none`. A grant other than `epics`, `stories`, `merge` or `release`, a `[` with no `]` on its line, or a `grants:` written as a YAML block list, stops it with the HLD's file and line. `/plan-epic` runs it before asking, and skips the question when it lists `stories`. |

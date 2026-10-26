# Reference

The detail behind [the guide](method.md): how each step works, every rule and every log. Read the guide first.

## The lead

The lead's messages to agents go through `swarm.sh tell`, which logs them as `tell:<kind>`, never a
bare `herdr agent prompt`.

When the board is in the project's repo, the lead's board edits (a re-scope, a new story, an
unblock) go through `swarm.sh board-pr`, each in its own worktree, never the main checkout. A board
outside the repo is edited where it is, and `board-pr` refuses it.

- `start <name>` makes `<repo>-wt/_board-<name>` on a new `board/<name>` branch from `origin/<base>`
  and prints its path. The `_` keeps it apart from story worktrees (`<repo>-wt/<slug>`), since a
  slug never has one. It refuses when the branch exists here or on origin (or origin cannot be
  read), when the directory exists, when the path resolves into the main checkout (through a
  symlink or `..`), and when `git worktree add` fails.
- `open <name> "<title>" <body-file>` refuses unless every changed file is under the board. Otherwise
  it commits with the brief's commit trailers, pushes, and opens the PR, printing its URL. A trailer
  is found anywhere in the brief, quoted in a sentence too: a `<Word>-by:` token, a name (with a
  letter, and no colon or quote), and an email in `<...>`. A placeholder such as `<who> <email>` is
  skipped, and the prose before a trailer never becomes part of it. Run `open` again to push
  more edits: it prints the open PR's URL and opens no second one. Once the branch's PR has merged
  or closed (squashed or not), it refuses, since the branch still holds the merged commits: run
  `done`, then `start` again. A PR counts as the branch's when its head came after the branch was
  started (the first entry in its reflog), so one from an earlier use of the name does not.
  `open scope-<epic>` also refuses when the worktree leaves `<epic>` at `status: split` (a large
  epic split into child epics, where the base has it at any other status) and `.swarm/<epic>/split-critic.json` holds no `{findings:[...]}`, or
  is older than the worktree (an abandoned draft's): the split critic answers before the board PR
  opens. Once it opens, `.swarm/<epic>/split-pr` records its day and URL for `flow`. A later
  `scope-<epic>` board PR on an epic the base already has split (a missed child, a split-gap fix)
  needs no critic and leaves that record alone.
  `open` also refuses, before it commits or pushes, when an epic goes `active` (new, or at the base
  with any status but `active`, `later`, `review`, `split` or `done`, a missing one too) with no
  ticket: an `agreed:` date the base's copy did not already have, a `parent:` naming another epic
  that is `active` or `split` on the base (not a draft, and not one the PR adds), or an `hld:`
  naming an HLD that is `agreed` and grants `epics` both at the base and in the worktree. It fetches `origin/<base>`
  first, and a failed fetch or read refuses. `lead_epics = on` skips the check. Commit the epic as `status: draft`, then run `/swarm-dev:epic <slug>`.
  `swarm.sh merge --board` refuses the same PRs (§ Merging).
- `done <name>` removes `board/<name>` on origin, then the worktree and the branch here, once the PR
  on the branch's tip (the local one, or origin's when there is none here) has merged or closed. A
  PR left by an earlier use of the name does not count. With no PR it removes an abandoned start:
  a branch with no commits past the base. It runs every check before it removes anything, and
  refuses while any PR on the branch is open, when origin cannot be read or its branch has moved
  past the local one, when the worktree at that path is not on `board/<name>`, has uncommitted
  changes or is locked, when `board/<name>` is checked out anywhere else (the main checkout, or
  another worktree), and when git cannot remove the worktree (giving git's reason). Origin's
  branch goes first, so when its delete fails the local state is still there for the next run.

Each step logs one `events.tsv` line, `board-pr:start`, `board-pr:open` or `board-pr:done`, with
the name and `ok` or the refusal. The name may be a story's slug, so these lines are never a sign
of life for that story's builder.


**The lead is woken when its queue grows.** While a conductor works, `/swarm-dev:swarm` waits on it, and
`swarm.sh next` names that conductor first. A story held or escalated mid-epic would sit unseen
until the conductor reports; on 2026-10-16, three held stories waited two hours that way. So the
lead also runs `swarm.sh wait --lead` beside the conductor's wait. Every 30 seconds
(`SWARM_LEAD_POLL`) it reads the board, and it returns as soon as a new item appears: a held story
(`held_for:`), an escalated one, or a story or epic in review whose PR heads are all green and that
waits on the lead's user: every one with `merge = human`, and with `merge = agent` only a PR
`swarm.sh merge` holds for them (§ Merging). It prints one line per item and logs one `lead-woken` line for each in events.tsv.
The lead handles each line at once and starts it again. It keeps what it last saw in
`.swarm/lead/seen`, so an item that lands between two runs wakes the next one. A new run stops
any earlier one, so only one is ever watching. It never nudges an agent and never edits the board.

**The lead is reminded to log what the user caught.** `/swarm-dev:swarm` tells the lead to run
`swarm.sh intervene user-caught "<what they found>"` as soon as the user finds a problem the swarm
missed. That rule lives only in the lead's prompt, and the lead forgot it: on 2026-10-25 the user
caught three problems and none was logged until they asked how such things reach the retro. So a
UserPromptSubmit hook (`hooks/user-caught-reminder.sh`) adds this line of context to each of your
messages to the lead: `If this message points out a problem the swarm or the lead missed, log it
first: swarm.sh intervene user-caught "<what they found>".` It runs only in the lead's session,
found as the lead's Stop hook finds it (`hooks/lead-session.sh`): no `SWARM_AGENT` or
`SWARM_GH_CALLER` in its environment (every agent has one), a cwd outside any worktree, and a swarm
project. Anywhere else it prints nothing. It never blocks a message.

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
   what you name.
3. **Say it is ready.** A reviewer (the `hld-review` role) attacks the draft, its `grants:` included:
   each grant hands agents a step you take today, so it names what goes wrong if the grant is
   misused. Its findings arrive in the co-author's pane.
4. **Agree it.** Your session sets `status: agreed`, opens a board PR with one codex pass, and
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
`lead_epics = on` (§ Settings) lets the lead set any epic active with no HLD at all; with it `off`,
the epic guard refuses an epic that goes active without an `agreed:` date, a `parent:`, or an `hld:`
whose HLD grants `epics` (§ The lead, § Merging).

## Decomposing an HLD

`swarm.sh next` names `plan-hld <hld>` for an agreed HLD with no `planned:` line, no epic carrying
its `hld:` and no plan worktree. `/plan-hld <hld>` (the file name without `.md`) then:

1. Works on origin's copy of the board in `<repo>-wt/_board-plan-<hld>`, never the main checkout.
   It stops when a plan PR for the HLD is open, and when the HLD is not agreed, has a `planned:`
   value or already has epics naming it. A leftover worktree from an interrupted run is resumed,
   or removed with `board-pr done` once its PR merged.
2. Runs a swarm: three surveys (`survey-code`, `survey-constraints`, `survey-overlaps`), one
   `hld-lead` that decomposes the HLD into epics (each independently shippable, with a **Done when**
   that could fail, its `areas`, and its **Your part**), a `skeptic-<slug>` per epic (at most five),
   one `codex` and one `critic`. Agents write JSON to `.swarm/<hld>/`, and a rerun reuses those newer
   than the worktree.
3. Writes one `epics/<slug>.md` per epic with `hld: <hld>`, sets the HLD's `planned: <today>` and
   fills its `## Epics` section with one link per epic. It changes nothing else.
4. Opens the board PR (`board-pr open plan-<hld>`) after one codex pass, with each epic `active`
   when the HLD grants `epics`; without that grant each epic is `draft`, and it asks you first.
   Findings are logged against the PR as in § Scoping an epic.

`swarm.sh grants` accepts that PR as under the HLD only in this shape: one `planned:` line, the
HLD changed after its last `## Epics` and nowhere else, at least one epic added, each a `draft` at
the PR's head unless the HLD grants `epics`, and nothing else touched. Under `merge = agent` the
lead lands it with `swarm.sh merge --board`, which reads no grant there; under `merge = human` it
does so only with `merge` granted, and otherwise you merge it. After the merge `next` offers
`plan-epic` for each active epic. Once every epic is built and gone from the board,
`swarm.sh finish <hld>` deletes the planned HLD in a board PR. It refuses a draft, a superseded
HLD, one with no `planned:` and one that still has epics.

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
   does not invent requirements, commit, or change `status`.
3. **Say it is ready**, to the co-author, in the same pane. A reviewer (the `epic-review` role, the
   most capable model at `xhigh` effort) starts on its own and attacks the draft: a problem with no
   evidence, goals that cannot be checked, an epic that contradicts an ADR or a safety rule, unnamed
   risks, open questions that would block planning it into stories. Its findings arrive in the
   co-author's pane; go through them there and revise until you are satisfied. You never switch
   tabs.
4. **Agree it**, to the co-author. Your session, waiting in the background, sets `status: active`,
   opens a PR for the epic (reviewed like any other change), and closes the co-author's pane. Only
   you can agree an epic; no agent changes its status, and `next` plans no draft epic.
5. **Hand over.** Run `/swarm-dev:swarm`. It sees an active epic with no stories and starts
   `/plan-epic`.

**What a good epic has.** Four sections: Problem (with evidence), Goals, Non-goals and
Constraints, and a **Your part** line. **Goals** are its **Done when**: checks that could fail,
because the conductor stops when they hold. **Non-goals** keep the plan from growing.

**Staged epics.** An epic in a staged HLD's Rollout carries `stage: v<x.y.0>`, the release that
ships it. This is an exception to step 4: a draft epic with both `stage:` and `hld:`, under an
HLD that grants `epics`, is set `active` by the lead, not by you through `/epic`, once the tag of the
previous minor, `v<x.(y-1).0>`, exists. A `v<x>.0.0` stage has no previous minor; its drafts go through `/epic`. A staged
draft with no `hld:`, or under an HLD without the `epics` grant, still goes through `/epic`. See
[Releases](#releases) for when a stage's release is cut.

**Stopping and resuming.** The epic is a file, so nothing is lost if you stop: run `/epic` on its
own (or `/swarm-dev:swarm`, which sees the draft) and a new co-author picks up the draft in progress
from the file; if there are several, it asks which. With no draft at all, it tells you where the
chain stands instead.

## Model and effort

Every agent's model and effort come from its role, set in one place: `policy()` in
`bin/swarm.sh` (`swarm.sh policy <role>` prints it). Spend on judgment, save on reading:

- **Design is Fable.** An epic is co-written at `high`, because the user waits on every turn, and
  attacked at `xhigh` before it is agreed.
- **Judgment is Opus.** An epic's decomposition into stories runs at `xhigh`. Skeptics and the
  critic run at `high`; a `risk: high` story gets a skeptic, and the critic checks every story.
- **Reading is Sonnet, chores are Haiku.** Surveys read and cite at `high`, since they feed the
  lead, and docs run on Sonnet at `medium`. Chores run on Haiku at `medium`: their result is a
  mechanical diff, checked by the conductor.
- **Building code is Opus at `high`**, and at `xhigh` for a story marked `risk: high`. To find out
  whether Sonnet would do as well, `sonnet_share = N` builds one in N of the other code stories
  marked `easy: true` on Sonnet at `high` (`code-sonnet`); every other code story stays on Opus.
  The slug fixes the pick, a retry goes back to Opus, and each build's agents.tsv line says which
  model built it. It ships off (`0`).
- **Codex is the cross-model check**, read-only, because a different model family shares fewer
  blind spots with the one that wrote the plan.
- **Below the design level, Fable is escalation only**: a story that failed twice, or an epic whose
  contradictions no one can reconcile. A story whose `attempts:` has reached `escalate_after` (2 by
  default) is built as `escalate`, on Fable at `xhigh`, ahead of `risk: high` and `sonnet_share`.
  A `kind: lead` story never escalates, since no agent builds it. `swarm.sh close <slug>` counts a
  failed build of a code, docs or chore story. When the story is still `ready`, its builder is still
  open and no PR on `story/<slug>` has merged or is open with auto-merge set, it raises `attempts:`
  by one and clears the attempt away: it removes the worktree and `story/<slug>`, here and on
  origin. The next build then starts fresh, and the third runs on Fable.

  While a PR on `story/<slug>` is open, a bare close closes the builder alone and puts the story in
  review with that PR, as `swarm.sh review` does (held instead, as review holds it, while a parent
  is open). The PR, its branch and worktree stay, nothing is counted, and close prints `kept:`
  naming the PR. It reads the head's checks and review once, and prints `kept (not green)` (or
  `checks not read` when gh could not tell), `kept (not reviewed)` or both when they have not
  passed. The story's state gets a `kept: <date> close <cause> (<what has not passed>)` line, so
  nothing takes it for reviewed: `status` and `wait --lead` list it as `kept: <slug> <PR URL> (not
  reviewed)`, never as one to merge, a conductor does not count it as in review for its epic's end,
  and `swarm.sh review <slug> <PR URL>` clears the line once it passes. It is logged as a `kept`
  event, never a `review`, so no report counts a give-up as a hand-off. The state is written before
  the builder closes, and goes back to `ready` when its pane cannot be closed. Reconcile then finishes the story when the PR merges, or sends it back to `ready`
  when it closes unmerged. `swarm.sh close <slug> [cause] --drop` clears the attempt even then,
  including after a bare close kept it (in review, or held) and its builder has gone, as long as the
  PR is open. It counts the attempt, sends a story in review back to `ready` once the count or hold
  is written (a step that fails first leaves it in review with its PR), closes each open PR unmerged with a
  comment naming the attempt, and prints each step that succeeded as `dropped:`, with the head SHA
  of each branch (read before it is deleted) and of each PR, so the work can be restored.

  Any other close after `review` or a merge, or after the builder has gone, counts nothing, and
  `reconcile` sending a story back to `ready` never counts. If gh cannot list the PRs, the close
  counts and clears nothing and says why on stderr; if its list cannot be read, nothing closes.
  `swarm.sh close <slug> <cause> [--drop]` also says why the builder stopped: `met`, `stalled` and
  `bound` count as above, while `impossible`, `paused` and `cleared-on-error` are not attempts and
  leave `attempts:` as it was. Those three hand the story to the lead and clear its build, so while
  its PR is open they are refused without `--drop`, before anything closes. `impossible` clears the
  build away whenever it hands the story on (below).
  `paused` and `cleared-on-error` clear it when the close ends a build under the same conditions; otherwise they clear nothing and print
  `not held:`. An unknown cause
  is refused before anything closes, and with `goal` on, so is a close with no cause while the story
  is `ready`. `impossible` means the builder replied `IMPOSSIBLE:`, so the **Done when** cannot be
  met: the story becomes `kind: lead` with `escalated_from:` and a block with the lead's choices
  (re-scope the **Done when**, then `swarm.sh reset <slug> <reason>`, or `swarm.sh drop <slug>
  <reason>`). Like a failed Fable build it is the lead's, with no **You:** step, so `next` prints
  `escalated <slug>` for it and it is never under waiting on you. `paused` and `cleared-on-error`
  hold the story the same way, with `held_for: <cause>`, whenever they clear its build. The lead lifts
  the hold with `swarm.sh reset <slug> <reason>`, which puts the kind back and keeps `attempts:`.
  That is not the story's one reset, and a later pause or error holds it again. `impossible` hands on
  any story still `ready` of a kind an agent builds, and clears its worktree and
  `story/<slug>` here and on origin so a reset builds it again. When the close lists the story's PRs,
  it closes each open one with `gh pr close`. When it lists none (its builder is gone, gh cannot list
  them), a bare close is refused before anything closes, because deleting `story/<slug>` on origin
  makes GitHub close any PR still open on that branch. With `--drop` it goes ahead, running no
  `gh pr close`, and the block says the PRs were not listed, so the lead looks before resetting.
  While a PR merged or is merging (auto-merge set), `impossible` is refused, `--drop` or not. Any
  other story, and a name with no story file, is refused before anything closes.
- **After Fable, the lead decides.** When the build a counted close ends was `escalate`, the close
  hands the story to the lead: `kind: lead`, `escalated_from:` its kind (`code (default)` when it
  had no `kind:` line), still `ready`, and a block with the attempts' PRs (from the same `gh pr
  list`) and the lead's two choices. The block is in `.swarm/escalated/<slug>`,
  not in the tracked story file. It has no **You:** step, because by the
  user's decision of 2026-10-15 the lead decides and then tells the user what it chose and why.
  `next` prints `escalated <slug>` for it, ahead of `gate`. The lead either re-scopes the story and
  runs `swarm.sh reset <slug> <reason>`, which removes `attempts:` and `escalated_from:` and deletes the block,
  or drops it. While the story still says `kind: lead`, reset puts its kind back (no `kind:` line
  for `code (default)`), so the file is its committed text again; a kind the lead set itself stays.
  A builder reads its story in its worktree, so when the board is in the story's repo the re-scope
  merges as a board PR first.
  Then the lead runs `reset` and pulls the board in one go: `reset` puts the file back to its
  committed text, so the pull brings in the re-scope, and `story` reads its kind, repo, epic and
  risk from that. `swarm.sh drop <slug> <reason>` takes a dropped story off the board as `finish`
  does, and it refuses any story that is not escalated. On a board in the repo, `finish` and `drop`
  never touch the main checkout: each deletes the file in the board PR `finish-<slug>` or
  `drop-<slug>` (titled `Drop <slug>: <reason>`) and prints the `swarm.sh merge --board <url>` that
  lands it; a second run pushes to the same PR. A file that is not on origin's base yet (an unmerged
  board PR adds it) is refused, and the worktree and branch the failed run started are removed. On a
  board outside the repo they delete the file where it is. A story is reset at most once: `reset`
  refuses a slug that events.tsv already shows reset, and names when, and a story that escalates
  again after its reset is offered only drop, in its block and in `next`. An
  escalated story is the lead's, so it is not listed under waiting on you (`status`, `dash`,
  `gate`). Each step is a line in events.tsv with its UTC time, for the training data:
  `escalate <slug>` when the build starts (`ok (attempt <n>)`), `dialog <slug>` when a conductor
  answers its usage-credits consent (`accepted` or `dismissed`), `escalated <slug>` at the close
  (`ok (attempts <n>, <k> PRs)`), and `reset` or `drop <slug>` with `ok (<reason>)`.
- **Measure before tuning.** `swarm.sh` records every agent it starts (role, model, effort,
  session) in `.swarm/agents.tsv`, and the `cost` section of `swarm.sh flow [--since YYYY-MM-DD]` turns that and Claude
  Code's logs into tokens and estimated cost per role. The lead's own sessions count too, under
  `lead`: every session in the project's Claude Code directory that agents.tsv does not name. Change
  `policy()` from that table, not from a guess.
- **The conductor is Opus at `high`, one fresh session per epic**, on the standard context window,
  never 1M. A conductor re-reads its whole context every turn: on the project this came from, one
  long-lived lead session was 80% of all tokens over three days (3.6B of 4.5B, at up to 1M
  context). The board carries the state, so a new conductor costs little.
- **A review agent is Opus at `high`**, the model the conductor reviewed with before each PR got its
  own (role `review`, started by `swarm.sh review-agent`). One per green PR, so reviews run side by
  side and the conductor's own context holds only the findings files.
- **The fallback reviewer runs on the model `fallback_reviewer` names, at `high`** (role
  `review-fallback`). codex-review starts it only when codex hits its usage limit and the key is set.

## Settings

The table in [the guide](method.md) lists every key. The rules the table leaves out:

- `merge` (default `human`): `human`: no agent merges, and a green, reviewed PR waits for you. The lead merges one only when the agreed HLD over it grants `merge`, and never a `costs: money` one (§ Merging). `agent`: the conductor merges, except a PR `swarm.sh merge` holds for you (§ Merging)
- `stall_minutes` (default `30`): a story's builder that is working this long with no sign of life (no commit in its worktree, no edit there to a file `git status` lists, no update to its PR, no swarm action on its story) is `stalled?`: `wait --stall` returns on it. `dash` shows every working agent's time since its last sign of life after its state (`working 12m`); past this it shows `stalled 40m` instead, marks the agent `!` and lists it under needs you (with `lead = session`, under the lead's queue). An agent with no story (a conductor or planner) has its own `events.tsv` lines as signs: those naming it, and once it has a start line, those its pane ran, nudges, resumes, incidents and failed tells excepted. Any agent with a Claude session, builder or not, also counts its session log (`.jsonl`). For `wait --stall` that is the newest entry of the agent's own work (an assistant message, a tool call or a tool result) in the log or in its Task subagents' logs (`<session>/subagents/*.jsonl`). Compaction, summary and background-task entries do not count, because a session hung on a command keeps writing them. `dash` still counts the log's last write. When `wait --stall` finds a builder stalled, its `stalled:` line, and the `incident` line it logs in `events.tsv`, end `; longest-running: pid <PID>, <N> min: <program> (under <parents>)` when a foreground Bash call is running a command. That call is the newest of Claude Code's Bash tool shells, and it must have started after the builder's last own work: a shell started earlier (a `run_in_background` server, say) is not the foreground call, and the builder is hung somewhere else. From that shell the line follows the oldest child at each step down to the leaf, so a hung `sleep` under `make test` names the `sleep`. Each process shows only its program name (ps's `comm`, so a path with spaces stays whole), never its arguments, which may hold a token. Processes outside a tool shell (caffeinate, an MCP or LSP server) are never named. When nothing is named, the line ends `; longest-running: none named (<why>)`: a codex builder, whose commands are not traced; no Bash tool call running a command; no tool shell started since its last own work; or a process list that could not be read. When the stall is stepped up (`escalate_ladder`), the `longest-running:` line follows `stepped up:` and says the step-up closed the pane, so the PID may be gone. The conductor checks the PID with `ps` and stops only a hung leaf with `kill <PID>`, then waits on the builder again; it closes the build as stalled when nothing is named or the builder stalls again. Working is its Claude session reporting busy, for `wait --stall` and `dash` alike, and herdr's working for a codex builder
- `queue_minutes` (default `30`): a story PR is queued when its head is green by `ci_gate`'s rule (every check run on every page and every commit status passed, at least one run), the last of them finished this many minutes ago, the PR is open and mergeable, its story is one an agent builds (never a `lead` story's), and that head has no review agent's review. A review counts when its findings file for the head is a pass (`## Findings`, no `head moved:`), or while the agent started on it (`.swarm/reviews/<slug>.head`) is still open in herdr with no file written: one that crashed, was closed or was tidied is no review. `watch` returns `queued: <repo> #<n> <branch> green <m>m with no review on <sha>` once per head, after it has reported the head's checks finished. `next`, while conductors work, prints the same line after its step's why for each such PR of every working conductor, ending in `(<conductor>)`, the one to send it to. A head is sent once: `watch` and `swarm.sh tell <conductor> note` (for each such line in the note) both record `queued <sha>` in `.swarm/state/watch-seen`, and neither `watch` nor `next` prints a recorded head again. `dash` and `status` do not look
- `sonnet_share` (default `0`): `N`: one in N `kind: code` stories marked `easy: true` and without `risk: high` is built on Sonnet (role `code-sonnet`), so `swarm.sh outcomes` can compare it with Opus. The pick is the `cksum` of the slug mod N, so a slug always gets the same model. Only a story's first build is picked: a retry is built on Opus, or on Fable once `escalate_after` applies. `0` is off (§ Model and effort)
- `escalate_after` (default `2`): `N`: a story an agent builds whose `attempts:` has reached N is built on Fable (role `escalate`), whatever its kind, risk or `sonnet_share` pick. An absent `attempts:` is 0, and a value that is not a whole number is refused. `0` is off (§ Model and effort)
- `escalate_ladder` (default empty): models from low to high, separated by commas, such as `sonnet,opus,fable`. Each must be one of the models building roles run on (`haiku`, `sonnet`, `opus`, `fable`), named once and in that order (a skipped rung is fine, as in `opus,fable`), or the config is refused, so a step-up never steps down or comes back to a model. Empty is off, and `swarm.sh step-up` refuses (§ The escalation ladder). On or above the top rung, where no step-up is left (above it is a model past the ladder's top, such as an `escalate_after` Fable build with `sonnet,opus`), `swarm.sh tell <slug> findings` does not send a builder its `top_rung_rounds`-th findings round since it got there (or since the lead last reset the story), or any later one: the story is held for the lead (`kind: lead`, `held_for: top-rung`, for `reset` or `drop`) with those findings in its block, and the builder and its PR are kept
- `step_up_findings` (default `3`): `N`: with `escalate_ladder` set, `swarm.sh tell <slug> findings` steps a builder up instead of sending it its Nth findings round of the build, and the step-up trigger is `findings-N` (§ The escalation ladder). A value that is not a whole number of 1 or more is refused, naming the key
- `top_rung_rounds` (default `2`): `N`: with `escalate_ladder` set, a builder on or above the ladder's top rung is not sent its Nth findings round since it got there (or since the lead last reset the story), or any later one; the story is held for the lead instead (`escalate_ladder` above). A value that is not a whole number of 2 or more is refused, naming the key: at `1` every findings round after the lead lifts a hold would hold the story again
- `builder_subagent_model` (default empty): a model such as `haiku`: the agents that build a story start with `CLAUDE_CODE_SUBAGENT_MODEL` set to it and `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`, so their subagents (an Explore search, say) run on it. Planners and conductors are unchanged. Empty leaves Claude Code's choice
- `goal` (default `off`): `N`, such as `goal = 5`: `swarm.sh story` writes each builder a goal condition beside its brief, in `.swarm/briefs/<slug>.goal.md`. It refers to the story by the path its brief gives (relative to the worktree when the board is in the repo it builds): every item under **Done when** and **From review**, if any, holds. Then it adds the reply the brief asks for, a way out (reply `IMPOSSIBLE: <why>` and stop) and `or stop after N more turns`. Claude Code queues a long paste as a prompt instead of running it as `/goal`, so a `/goal` message over `GOAL_SEND_MAX` characters stops `story` before it makes a branch or worktree. Needs Claude Code 2.1.269 or later. Once the brief is taken up, `story` sends the builder the goal and fails if its session log does not show it set (§ Building, **The goal.**)
- `codex_minutes` (default `10`): `swarm.sh codex-review <base>`, which every brief and the lead use to run codex's review, stops codex after this many minutes: TERM to its whole process tree, a few seconds' grace, then KILL to whatever is left. It then prints `codex skipped: timed out after <N> min` and exits non-zero, and its events.tsv line says the same. It ships on (§ Scoping an epic)
- `fallback_reviewer` (default empty): a model such as `sonnet`. When codex reports a usage limit, `codex-review` starts a review agent on it in codex's place (role `review-fallback`), waits for its findings and prints them in codex's form. Empty keeps `codex skipped: usage limit`. § Building has the details
- `lead` (default `off`): `session`: a lead session acts for you, so `dash` splits needs you in two. Needs you keeps only your steps: a story with a **You:** step and an expired login. Every merge row (with `merge = agent`, a `costs: money` merge row stays under needs you), an agent waiting on a prompt, a `lead` story with no **You:** step, every escalated story, an empty pane, an agent whose session is gone or unknown, and a stalled agent go in a `lead's queue` box under it, left out when empty. `next` and `status` are unchanged
- `merge_admin` (default `off`): `on`: `swarm.sh merge` passes `--admin` to `gh pr merge`, so it merges in a repo whose ruleset requires an approving review, which no agent can give. It does so only after the checks it always makes: the head is green, no `costs: money` hold applies, the `--board` or `--release` scope holds, and the head is the one `--head` names. `--admin` skips every rule on the base, not only the review, so `swarm.sh merge` first reads the base's rulesets and branch protection itself. It refuses while a status check they require is absent from the head, while they require the branch up to date (strict) and the head is behind the base, and whenever they hold a rule besides the review, the status checks and rules about pushes (deletion, force pushes, creation): a merge queue, required workflows, signatures, linear history, conversation resolution, deployments, code scanning or push restrictions. That includes the review rule's own thread resolution, and merge methods that leave out the one `swarm.sh merge` picks from the repo's settings. A classic protection field outside the few known to be safe is refused whatever its name, and a 404 from branch protection counts as unprotected only when GitHub says `Branch not protected`, since a token that cannot read protection gets a 404 too. The refusal names the rule. A red head, a held PR or a moved head is still refused before `gh pr merge` runs. Off, `swarm.sh merge` never passes `--admin` and reads none of these
- `lead_epics` (default `off`): `on`: the lead may set an epic `active` on its own. `off`: an epic goes `active` only through the user or a grant. Any other value stops `swarm.sh` with the file and line
- `commit_trailers` (default empty): one or more trailers, `;` between them, such as `commit_trailers = Co-Authored-By: Ann <ann@example.com> ; Signed-off-by: Bo <bo@example.com>`. Each is a `Token: value` pair; anything else is refused. A `#` starts a comment, so no trailer can hold one. Every builder's brief tells it to end each commit message with them, one per line, and `swarm.sh board-pr` adds them to its commit, ahead of the trailers the brief names. `swarm.sh init` writes the line commented out
- `agent_env` (default empty): variable names, separated by spaces, that every agent gets with the values of the session that starts it, such as a provider's key (§ Building, **The agents' environment.**)
- `TEST_FILE_TIMEOUT` (default `600`; not a `swarm.sh config` key, an environment variable of `scripts/test.sh`, which `make test` runs): a whole number of seconds a test file may run. Past it, `test.sh` stops the file's process group (TERM, KILL after 2 s) and fails it as `TIMEOUT <file> after <n>s`, printing its last 20 lines. A file in the Makefile's `SLOW` gets three times the limit. Anything but a whole number of 1 or more is refused. `SWARM_SLEEP_SCALE` defaults to `0.01` in `test.sh`, as in the Makefile. `test.sh` unsets every other `SWARM_*` variable, so a test never sees the `SWARM_PROJECT` that points a builder's pane at its real project. It also sets `SWARM_NO_CI_REFRESH=1`, and dash starts no detached ci refresh while `SWARM_SLEEP_SCALE` is set. Each file runs from its own `TMPDIR`, outside any git repo, so a `swarm.sh` call a test leaves unpinned (no `cd` into its project, no `SWARM_PROJECT`) stops at "not in a swarm project" instead of reaching the checkout's `.swarm` logs

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
`.swarm/<epic>/`. The user sees refuted stories, contradictions, the risky stories and stories ÷
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

## Building

`swarm.sh conduct <epic>` starts a fresh conductor that drives the epic's stories to merge, then
stops and reports; the session it was started from stays free. Its last act is writing that report
to `.swarm/conduct-<epic>.report.md`, and that file, not the agent going idle, is how
`/swarm-dev:swarm` knows it has finished: a conductor is idle whenever it waits on its own
background work. When it starts, an epic still `later` is set `active` (in
`.swarm/board-state/epics/<slug>`, which `conduct` reports in one line), so `status` and `next`
stop listing it as waiting on you. It runs in a herdr workspace named for the epic's `parent:` if it has one (epics with the same
parent share it), or else for the epic, in a tab named for the epic, in a pane named `conductor`. Each story it starts gets a pane in
that tab, named for the story; a tab holds four panes, and the fifth opens `<epic>-2`. A one-off
story gets a tab of its own. Conductors of different epics can run side by side (each watches only its own epic's PRs, with
`watch --epic`, and a fix-main story's, which every conductor builds and merges first), as long as their stories touch different files; shared files are the lead's alone.

**The backlog conductor.** `swarm.sh conduct --backlog` starts `conduct-backlog-<dir>-<hash>` (the
first 9 characters of the project directory's name, then 6 hex characters of a checksum of its path), which builds the ready stories with no `epic:` (the one-offs) the way an epic's conductor builds an epic: waves with
`story --strict`, the same review, and the same handover or merge. It runs in a workspace named
`backlog` and needs no epic file; a board with an `epics/backlog.md` makes it refuse. herdr's agent
names span every project, so naming it for the project's path lets two projects each run one at once,
even two directories with the same name. A name another project's agent holds is refused before the
old report or brief is touched, and the refusal says where that agent runs. An epic whose
conductor would take that name (`backlog-<dir>-<hash>` for this project) is refused too. It watches only
its stories' PRs (`watch --backlog`), and a story whose worktree already exists has started, so it
waits on that builder and never starts the story again. Its report,
`.swarm/conduct-backlog.report.md`, lists each one-off it could not start as
`not started: <slug> (<why>)`. With `merge = human`, a story refused because another of its
one-offs is in review is reported as `not started: <slug> (waits on <other>'s merge)`, since that
merge cannot happen while the conductor runs. `/swarm-dev:swarm` runs it for a `story` or `resume`
step. Until a story or epic is added, changed or removed under `stories/` or `epics/` (a merge
removes one), it starts no new backlog conductor while that report exists, whatever the report
says, and tells you why the story waits. For a `resume` step it also stops when the report lists
the story under `not started:` (a build that died), even after the board changes. If story/<slug>
has commits worth keeping (`git log origin/<base>..story/<slug>`), push it and open a PR from it.
Otherwise clear the stop by discarding the build from its repo
(`git worktree remove --force ../<repo>-wt/<slug>`, `git worktree prune`,
`git branch -D story/<slug>`, and `git push origin --delete story/<slug>` if it was pushed), then
deleting `.swarm/conduct-backlog.report.md`. A fix that touches no story or epic, such as a code PR
that turns CI on the base green, does not clear the stop either: once the cause is fixed, delete
`.swarm/conduct-backlog.report.md`.

Conductors also start on their own, the backlog's and an epic's alike: after `swarm.sh merge
--board` lands, once it has sent its notes (a conductor's own board merge included), and from
`swarm.sh next` when its step is `wait <conductor>`. For each active epic with a ready story an agent
builds (`kind` code, docs or chore) and no conductor running, it runs `swarm.sh conduct <epic>`; for
such stories with no epic, `swarm.sh conduct --backlog`. A conductor still in its pane counts as
running. When it has written its report, it prints `no conductor started: <conductor> has reported;
collect it first`: a new start would delete that report before the lead reads it. A conductor whose
pane is gone (closed by hand, a herdr restart, a crash) and whose report nobody collected (no `close`
of it in `events.tsv` since the report, as collect's `swarm.sh close` logs) gets `no conductor started:
<conductor> is gone, and nobody collected <report>; read it, then delete it`. When another
project's agent holds the conductor's name, it says so and starts none. A draft, `later` or `split` epic's stories start nothing, and
neither does a `fix-main-*` story, which every running conductor builds first. No conductor starts
for an epic or the backlog, and it says why, while that conductor's report is newer than every story
and epic file, and than the state files swarm.sh keeps in `.swarm/board-state` for that epic and its
ready stories (an `unblock` or a `reset` readies a story there): a new one would stop as the last did.
Another epic's state writes do not count. Nor does a backlog conductor start while its report
lists a one-off whose worktree is still there under `not started:` (the stops above). Nothing starts
while a working conductor has stopped on an expired login or an API error, which would stop a new one
too, or while herdr cannot list its agents, since what runs is then not known; each prints why.
Outside herdr it starts nothing and prints the `swarm.sh conduct` to run. Each start prints `started:
<conductor> (swarm.sh conduct <arg>)`, which `next` puts after the wait's why, so its first line is
still the step, and logs a `conduct` line in `events.tsv` as `swarm.sh conduct` does. A start that
fails prints a warning, logs its error as that line's outcome, and changes neither command's exit
status. The warning says to run the `swarm.sh conduct` yourself, or, when an agent's own board merge
started it with only that agent's environment, that the lead's `swarm.sh next` starts it. `dash --check` and `/epic` read next's step with `swarm.sh _step`, which starts nothing.

**The agents' environment.** herdr starts each agent in a pane's shell, which holds everything you
exported. Before the agent starts, swarm.sh has that shell replace itself, through `env -i`, with
`zsh -f` (no rc file runs) holding only:

- `PATH`, `HOME`, `TERM`, `USER`, `LOGNAME`, `TMPDIR`, `LANG` and the `LC_*` variables;
- where logins, config and logs live: `CLAUDE_CONFIG_DIR`, `CLAUDE_PROJECTS_DIR`, `CODEX_HOME`,
  `GH_CONFIG_DIR`, `GIT_CONFIG_GLOBAL`, `GNUPGHOME` and the `XDG_*` directories;
- the session bus, `DBUS_SESSION_BUS_ADDRESS`, through which `gh`'s keyring token and
  `git-credential-libsecret` reach the Secret Service on Linux;
- for a push: the ssh agent's `SSH_AUTH_SOCK` and `GIT_SSH_COMMAND`;
- for a proxy or an intercepting CA: `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY` and their lowercase
  forms, `SSL_CERT_FILE` and `NODE_EXTRA_CA_CERTS`;
- which provider and model Claude Code uses: `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`,
  `CLAUDE_CODE_USE_FOUNDRY`, `ANTHROPIC_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`, `AWS_REGION`,
  `AWS_PROFILE`, `CLOUD_ML_REGION` and `ANTHROPIC_VERTEX_PROJECT_ID`;
- swarm.sh's own `SWARM_*` settings, with `SWARM_PROJECT` as the project's absolute path, so the
  agent's own `swarm.sh` finds the same project and settings from any directory;
- `SHELL`, set to that zsh; `ZDOTDIR`, set to the agent's own `.swarm/zdotdir/<agent>`; and
  `GPG_TTY`, set to the agent's own terminal, so pinentry asks there and never in yours. swarm.sh
  makes the `ZDOTDIR` afresh, 0700, at each launch, with only a `.zshenv` and a `.zprofile` that
  put back the `PATH` a login shell was given once `/etc/zprofile` has run (on macOS, its
  path_helper puts `/usr/bin` and `/bin` first), and removes it when `swarm.sh close` closes the
  agent;
- `HERDR_ENV=1`, and those of herdr's own variables for the pane that the pane has.

The others take swarm.sh's value, when it has one, except herdr's, which come from the new pane. A
story's `env: [NAME, ...]` adds those names for its builder, whether `story` starts it or a conductor
restarts it with `swarm.sh agent`. A conductor gets the names of its epic's open (`ready`, `blocked`
or `review`) code, docs and chore stories (for `conduct --backlog`, those with no epic), so the
builders it starts can receive them; a `lead` story's names stay with you. A conductor has only the
names its stories had when it started: for a story added later with a new name, restart it with
`swarm.sh conduct <epic>`, which its refusal names. Each value comes from the session that runs
`swarm.sh`. `story`, `agent` and `conduct` refuse, before anything starts, an `env:` that is not a
one-line `[A, B]` list, a name that is not `[A-Z_][A-Z0-9_]*`, a name that session does not have,
and a reserved name: one from the list above or starting `LC_`, `SWARM_`, `XDG_` or `HERDR_`; the lead's
own Claude Code session's (`CLAUDECODE`, `CLAUDE_CODE_*`, `CLAUDE_PID`); and one that loads code
into what the agent runs (`BASH_ENV`, `ENV`, `DYLD_*`, `LD_*`). No value goes through a command line:
swarm.sh writes them to a 0600 file under `.swarm/launch/`, which the pane's shell runs and which
deletes itself, so the pane's scrollback shows the launch line with no value in it.

`agent_env = NAME ...` in `.claude/swarm/config` adds names for every agent of every role: the HLD
and epic co-authors, planners, conductors, builders and review agents. A restart keeps the names.
`swarm.sh upgrade` gives them the values of the session that runs it. When herdr restores a pane, the
values come from that pane's new shell, since swarm.sh never writes a value to disk. So a key you
export only in the session that started the agent is gone after a herdr restore; export it from your
shell's startup files to keep it there. This is how a provider's key
reaches agents. On Azure Foundry, for example, Claude Code needs `ANTHROPIC_FOUNDRY_RESOURCE` and
`ANTHROPIC_FOUNDRY_API_KEY`, and the `ANTHROPIC_DEFAULT_*_MODEL` names if your deployments are named
differently from the models. Without them every agent stops at its start. Each value comes from the
session that starts the agent. A name that session does not have is skipped with a warning, so the
same board still runs from a session without the provider. When the config loads, `swarm.sh` refuses
a name that is not `[A-Z_][A-Z0-9_]*` or is reserved, by the same rules as `env:`, and names the line.

By default, a login read from the environment does not reach an agent either: `ANTHROPIC_API_KEY`,
`CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, or a `GH_TOKEN` for `gh`. A story can name
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY` or `GH_TOKEN` for its builder (never a `CLAUDE_CODE_*` one).
Agents with no story of their own (planners and review agents, and conductors beyond their stories'
names) get one only when `agent_env` names it, and then every agent gets it. Otherwise, log in
through each tool instead: `claude` then `/login`, `codex login`, and `gh auth login`. On Foundry, Bedrock or Vertex, the provider and model
selection above passes from the session that runs swarm.sh, or can go under `env` in
`~/.claude/settings.json`, which every Claude Code session reads. The credentials come from the
provider's own login or profile files (`aws sso login` or a profile in `~/.aws`,
`gcloud auth application-default login`). An exported secret such as `AWS_SECRET_ACCESS_KEY`
reaches agents only when `agent_env` names it. Foundry is the exception: its endpoint and key exist
only in the environment, so when `CLAUDE_CODE_USE_FOUNDRY` is `1` or `true`, every agent also gets
the session's `ANTHROPIC_FOUNDRY_*` and `ANTHROPIC_DEFAULT_*_MODEL` variables, with no `agent_env` line.

Because `SHELL` is zsh and `ZDOTDIR` is empty, every shell an agent starts later, such as Claude
Code's Bash tool and codex's commands, reads none of your `~/.zshenv`, `~/.zprofile`, `~/.zshrc`,
`~/.zlogin`, `~/.bashrc` or `~/.bash_profile`, even when your own shell is bash. Only the system
files in `/etc` (`zshenv`, `zprofile`, `zshrc`, `zlogin`) still run, and a login shell's `PATH` is
put back as it was given after them.

**Board state.** swarm.sh keeps the front-matter keys it writes (`status`, `prs`, `attempts`, `kind`,
`escalated_from`, `held_for`, `held_by` and `kept`) out of tracked story and epic files. `review`, `unblock`,
`close`, `reset`, `reconcile` and `conduct` write them as `key: value` lines to
`.swarm/board-state/stories/<slug>` or `.swarm/board-state/epics/<slug>`, so a story and an epic with
the same slug keep separate state, and `git status` in the main checkout stays clean. Every command
reads a key from that file first and from the item's front matter second, so a key with no line
there, as on an existing board, reads from the file. `dash` reads its board rows the same way. A line
with no value clears the key, and swarm.sh writes no line that would only repeat the file's value.
Beside each line it keeps a `<key>@base:` line with the file's value at the time.
Once the file's value differs from that (a board PR set the epic `later`, say), the file's value is
read, and the next write to the item drops the old line. A write holds the item's lock, a
`<slug>.lock` directory beside its state file, so two commands writing one item at once keep both
changes; a command that finds the lock still there after 10 seconds stops and names it, as one
does when a state file cannot be read or written. The
escalated block `close` writes for the lead is in `.swarm/escalated/<slug>`. Deleting an item's file
where it is (`reconcile`, `finish` or `drop`, on a board outside the repo) deletes its state file
and escalated block too. `reconcile` also deletes them when an item's PR marked it `done`, and, on
a board in the repo, for each story or epic a commit deleted (its PR or a board PR), whether
reconcile pulled that commit or you did: the file is in neither `HEAD` nor the main checkout. A file
removed only by hand, or never committed, keeps its state.

**Pick the wave.** Only `ready` stories that do not clash. Two stories clash only when their
`touches` name the same `file:symbol` in the same repo, or when either names the bare file of a file
the other also names. Otherwise both build at once, even in the same file: git merges edits to
different parts of one file, and a story names the functions it changes. A builder whose PR
conflicts with its base merges its base in, resolves it, reruns the tests and pushes; a conflict
never sends a story back to `ready`. The conductor sends that as a `nudge` tell, which is not a
review round. It waits first for a builder that is working, and starts a builder in the story's
worktree when the one it had was closed after `swarm.sh review`.
Work that edits a shared file (`AGENTS.md`, root config, schemas, hygiene scripts) is done by the
lead, alone.

A wave only sees its own epic, so `story` also looks across epics. Before it makes anything, it
compares the story's `touches` with those of every story in another epic (a story with no epic
counts as another). If one of them is open (in review, or `ready` with its builder open) and touches the
same function or file, `story` prints `warning: <other> (epic <e>) is open and touches <entry>;
start <slug> after it merges` and starts the story anyway. `story --strict` refuses instead, naming
the other story, and leaves no branch, worktree, pane or brief behind. It also refuses when herdr
cannot list its agents or the board's `touches` cannot be read, where plain `story` warns that it
cannot tell. Then nothing is known to be open, so the message says to retry the story, not to wait
for a merge. `--strict` may come before or after the slug. Conductors always pass
`--strict`.

A `<file>:<fn>` entry matches the same fn in the same file, and a file-only entry matches anything
in that file. An entry with no `/` or `.` before its `:` names a fn in the previous entry's file and
repo, so `bin/swarm.sh:config defaults, CONFIG_KEYS` covers `bin/swarm.sh:CONFIG_KEYS`. When the
entry's own repo (its prefix, or the story's `repo:`) has a file of that name, it is that file
instead, so `Makefile` or `Makefile:lint` after another entry still matches. A `<repo>: ` prefix sets the entry's repo, and otherwise the
story's `repo:` does; the same file in another repo does not match. Parentheticals are dropped.

**Stacked builds.** A story need not wait for its parents to merge. `swarm.sh unblock` also readies
a blocked story that has no build yet (no worktree and no `story/<slug>`) when each `depends_on` slug
is finished or is an open story in the same repo with an open PR (in `review` with a `prs:` line, or
one that `gh pr list --head story/<p>` finds), and prints `ready: <slug> (stacked on <parents>)`. A
parent that is blocked, has no open PR or lives in another repo keeps the story blocked, and so does
a gh failure. A story that only an old build keeps from starting stays blocked too, printed as
`not stacked: <slug>` for the lead. `story` fetches each parent's branch and checks that its PR is still open. If one is not,
the story goes back to `blocked` and nothing is made. Otherwise the worktree starts at
`origin/story/<first parent>` with each other parent's branch merged in, events.tsv gets a
`stacked <slug>` line, and the brief says to open the PR against the base with
`Merge after <parent PR URLs>` in its body. A merge conflict fails, naming the two branches that
conflict and their files, and leaves no worktree or branch. The overlap check skips a story's own
parents and its own children, so neither holds the other back under `--strict`. While a parent is
still on the board, `swarm.sh review` holds the child: it sets it `blocked` with `held_by: <parents>`,
keeps its `prs:` line, builder, worktree and branch, puts nothing in review, and exits with
`held: <slug> waits for <p> to merge`, pointing at the child's Stacked line for what comes next. A held child still counts as open in the overlap check, since
its PR is. With `merge = human` the conductor then closes the child's builder with a bare
`swarm.sh close <slug>`, which counts nothing for a blocked story; with `merge = agent` the builder
stays open. When a parent's branch moves, the conductor tells the child to merge it in. A held child
is readied again only once every parent has finished, as `ready: <slug> (held: merge origin/<base>,
review again)` while its worktree is still there. With the worktree gone it is readied plainly,
without `held_by:` or the `prs:` line, and `story` builds it fresh. A parent squash-merges, so its
commits reach the base under new hashes: the child's builder (a new one in its worktree, when it was
closed) merges `origin/<base>`, and the child is reviewed again. `swarm.sh status` prints the same
instruction as the child's Stacked line, and the conductor acts on that line alone; a
`could not check` line there means nothing is known yet, never that the base is in. A review that
passes clears `held_by:`, and so does clearing the build (a counted, impossible, paused or
cleared-on-error close), which also drops the `prs:` line the hold kept. `story` refuses any story
whose worktree or branch already exists, and points a held one at its Stacked line.
Parents always merge first: you are never handed a child before its parents, and `swarm.sh merge`
refuses one too, since it merges only an item in review.

```bash
swarm.sh story [--strict] <slug>   # worktree on story/<slug>, a pane, the agent, its brief
swarm.sh wait <slug>       # in the background: returns when it settles
swarm.sh wait --until-report conduct-<epic>   # in the background: returns when the conductor reports
swarm.sh watch             # in the background: returns when a story PR needs the lead
```

`wait` returns when the agent's Claude session reports `idle`, `waiting` (printed with what it
waits on, such as `waiting: permission prompt`) or `gone` (its session has no entry in `claude agents
--json`, or one with no status: the process exited), which can be early. herdr's `agent wait` is only the wake-up, in
STALL_POLL_MS slices (a minute); after each wake or slice `wait` reads the session once, and never
herdr's word for it. A session Claude Code gives no state for (`unknown`, or the list call failed)
is waited on, said once on stderr. At the timeout `wait` prints the last state and exits 1, and so
it does at once when herdr's wait fails other than by timing out and the session has not settled.
A conductor is idle whenever it waits on its own builders, so `wait` on one holds until its report
exists, its session is waiting or gone, or its login expired. `wait --until-report`, which
`/swarm-dev:swarm` runs, does that with no timeout: an epic that takes more than an hour is not cut
short. It takes only a conductor's name and fails on any other.
A codex agent, or one with no recorded session, is waited on through herdr's status. `wait`
listens on herdr's event stream (the socket at `HERDR_SOCKET_PATH`, which herdr sets in every pane)
and returns the moment herdr says the agent is `idle`, `blocked` or `done`, or `gone` when its pane
closes or exits. With no socket, or a stream that fails, it falls back to herdr's `agent wait` for
the rest of each slice. A builder
whose session goes idle while its story is `ready` and has no open or merged PR (a closed one is an
earlier attempt's) has stopped early, perhaps on a failed request, and nothing else would wake it. `wait` tells it
why ("you are idle and story/<slug> has no PR") and waits again, up to three times. Nudges are at
least a slice apart unless the session turns busy in between. If herdr cannot deliver a nudge,
`wait` stops there and returns idle, and logs nothing for it. With `goal` on, `wait` nudges no builder, whatever its session log shows: a nudge would bury the reply and the goal entry the conductor reads the cause from, so `wait` returns idle and the conductor reads why it stopped. Only code, docs and chore stories are
nudged, never a conductor or a planner, and a gh or git call that fails counts as a
PR. An idle agent whose transcript (its session's `.jsonl`, the file flow's `cost` section reads) ends on Claude
Code's "Login expired · Please run /login", with no message sent to it since, is never nudged or
waited on: `wait` prints `auth` at once,
with a line on stderr naming it, for a builder and a conductor alike. Only the user's `/login` clears
it. Once they have run it, tell the agent to resume (`swarm.sh tell`), and a conductor tells the same
to each builder whose `wait` printed `auth`.
A turn can also stop on an API error while the session still reads busy, because background shells
the agent opened are still running. When herdr says the agent is `done` or `idle` and the last thing
in its pane is Claude Code's own error line (`⏺ API Error: ...` at the left margin, with no reply or
submitted prompt after it; the input box, which may hold a suggestion, is not read), `wait` sends it "Your last turn stopped on an API error; carry on where you
stopped." and waits again. It logs each one as a `resume` line, not a nudge, conductors included. After three such stops
in a row (a turn that ends any other way resets the count), or if the message is not taken up, `wait`
prints `stuck: api error` and exits 4. A pane that still shows the old error after a resume (the
message has not shown yet) is no new stop. An idle session still on that same pane a slice later
never took the message up. With `goal` on it never resumes a builder: it returns
`stuck: api error` at once, so the transcript still ends on the error for the goal rule. A conductor
or review agent is resumed either way. When the transcript ends on an expired login, `wait` prints
`auth` instead, busy session or not, and resumes nothing. `tell`
treats such an agent as idle and delivers, and `next` names a conductor's stop. Any `wait` also
prints `stuck: no output for <N>m (<pane>)` and exits 4 when a busy agent (its session busy, or
herdr's working for one herdr answers for) has not changed its pane for `stall_minutes` and its
transcript shows no background task still running (a shell, an async subagent or a monitor it
started, with no `<task-notification>` carrying a `<status>` for it since). It sends nothing then: read the pane. `stuck` is
not a stall, and no close follows from it. When an agent's pane shows Claude Code's usage-limit dialog
("Stop and wait for limit to reset" / "Wait here, then continue automatically"), `wait` picks
"Wait here, then continue automatically" (the user's standing choice) once per dialog (a keypress
herdr fails to send is tried again on the next pass), logs one
`usage-limit` event for the agent in events.tsv, and keeps waiting. Only the live dialog counts: its
options among the pane's last lines with no input box under them, so a prompt quoting it sends nothing. A pane already waiting after that choice ("Usage
limit reached" with "limit resets" or "Continuing shortly") is handled the same way, with no keys
sent, while the session is busy or waiting; an idle session under that line is idle. Neither counts as a nudge or a resume, and neither turns into `stuck: no output` however long
it sits; at its timeout `wait` prints `usage-limit` and exits 1. Until the pane moves on, `status`
and `dash` show `usage-limit` for the agent in place of working or idle. `wait --stall
<slug>` also returns, with exit code 3 and `stalled: working <N> min with no commit, edit, own work in the session log or PR update`, when the
builder (busy, as above) has shown no sign of life (a worktree commit, an uncommitted edit in the
worktree, its own work in its session log, a PR update, a swarm action on its story) for `stall_minutes` since that wait began; the line names the longest-running command the builder runs, as under `stall_minutes`.
So `wait` exits 0 when the agent settles (idle, waiting, gone or `auth`), 1 at the timeout or when
herdr's wait fails, 3 on a stall (`--stall` only) and 4 when stuck. `watch` is what the lead waits on: it
exits when a story PR's checks finish, when it conflicts with its base, when its head has had no checks
for 10 minutes, when it is queued (green and mergeable for `queue_minutes` with no review agent on
its head, reported once per head), or when an agent's session is waiting, and it names what the agent waits for. It polls the open PRs every minute over gh's REST API, whose hourly limit is separate from the GraphQL one that `gh pr` commands spend: the list, then a PR's mergeable state, read only for its own stories' PRs and only when a conflict or a queued line could follow from it, so never for a head it has reported conflicting, or finished and queued. A poll that reports one PR reads nothing past it. A failed read counts as `UNKNOWN` for that poll and is said on stderr. A failed list is said once, until a list succeeds again, and watch polls on. A failed check-runs read counts as unknown for that poll and is said once per PR, with gh's reason, until a read of that PR succeeds. A codex
agent, or one with no session recorded, counts as waiting when herdr says it is blocked. Each agent's
wait is reported once, and again only after a poll finds that agent no longer waiting; a poll that
cannot read the agents changes nothing. herdr lists every project's agents, so
`watch`, and `next` when it looks for a running conductor, count only agents in panes this project
opened (recorded in `.swarm/state`); an agent started by hand is not watched.

**The goal.** With `goal = N`, once the builder has taken up its brief, `story` sends it `/goal`
followed by the condition in `.swarm/briefs/<slug>.goal.md`, joined onto one line, once, through
`herdr agent prompt`. The condition names the story by its path, so the line stays under
`GOAL_SEND_MAX`, the length past which Claude Code takes it as pasted text. The builder is mid-turn by then; Claude Code still sets the goal straight
away, and runs one extra short turn after the brief's turn ends. From then on Claude Code's judge
keeps the builder working until the story's **Done when** holds, the builder replies
`IMPOSSIBLE: <why>`, or N more turns have passed. The judge records all three as met, and only its
reason text tells them apart. `story` looks for the goal in the builder's session log and does not
read the pane: it waits up to a minute for a `goal_status` entry with that condition (whitespace
aside), written after the send. If Claude Code refused
the goal (hooks restricted by settings or policy, or a folder it does not trust), or no entry came,
`story` fails, names the story and the reason, and leaves the builder open for the lead to look at.
If the log shows the `/goal` queued as a prompt instead, the failure says it was pasted as text.
It never sends the `/goal` again, because a second one would reset a goal that had set.
It types the `/goal` only once Claude Code reports the session busy. If the session is waiting on a
prompt, where Enter could approve what auto mode flagged, or is not busy within a minute, nothing is
typed and `story` fails. A failure after the brief went in says the brief was delivered, so no one
sends it again.
Once the builder takes up findings from `swarm.sh tell <slug> findings <file>`, `tell` sends it a
fresh `/goal` in the same turn, under the same rules. The goal holds until each finding is fixed, or
declined with a reason in the reply, and the builder has sent the reply its brief asks for, or until N
more turns have passed. `tell` fails and names the story unless the session log shows that goal set
after the tell began, and its message says the findings were delivered. A nudge or resume tell sends
no goal.

**Giving up on a builder.** A conductor gives up on a builder when `wait --stall` returns stalled,
when it is idle with no PR after wait's nudges, or
when review has not converged in the rounds it allows. It runs `swarm.sh close <slug> --drop`, which, on a
code, docs or chore story still `ready`, counts the attempt and clears its worktree, branch and PR,
and starts the story again in a later wave with
`swarm.sh story --strict <slug>`; swarm.sh picks the model, Fable once the story has failed `escalate_after`
builds (2 by default). With `escalate_after = 0` it reports a story that has failed twice to the lead
instead. A story that comes back `kind: lead` with `escalated_from:` is the lead's to decide, never
the user's. With `goal` on, a builder idle short of its reply is not nudged: the conductor reads the
cause from its reply and the last met `goal_status` entry's `reason` in its session log, closes it with
`swarm.sh close <slug> <cause> --drop` (`stalled` for a stall), and on `cleared-on-error` starts nothing more
in the wave and lists the story for the lead. A Fable builder can stop on its usage-credits consent, which `wait` prints as
`waiting: dialog open`. Only for an escalate build, and only once `herdr agent read` shows that
consent, the conductor accepts it with `herdr pane send-keys` in the builder's pane, runs
`swarm.sh dialog <slug> accepted` (or `dismissed`, telling the lead), which logs `dialog <slug>`
with its time, and waits on the builder again. It never closes or tells a builder over a dialog, and
a dialog is not an attempt. Any other dialog, and every permission or tool prompt, it leaves alone.
`/swarm-dev:swarm` does the same for the lead's one-off stories.

**Watching it.** `swarm.sh status` lists the agents that need a look (waiting on a prompt, an empty
pane where a start failed, a session gone or unknown, or `auth`: an idle agent whose login expired,
which only your `/login` clears), what waits on you, and the next step. A Stacked section, shown
only when it has a line, lists each stacked build that has to catch up with a parent. It reads the
parents the child's current build stacked on, and compares them with the child's branch on origin,
so a merge the child has not pushed still shows: `<child>: merge origin/story/<p>` when the parent's
open PR has commits the child lacks, `<child>: merge origin/<base> (<p> merged)` once the parent
merged and the child lacks the base's head (one line for all the merged parents; after a squash
merge, the child takes the base), and `<child>: lost story/<p>` when the parent's PR closed unmerged
(as a dropped parent's has), or its branch is gone while its PR is open or, still on the board, it
has no PR. A gh or git call that fails, or a git that cannot tell, gives a `could not check` line.
Inside herdr, a line ends `(no builder)` when the child has no builder open. After each wait, watch
and new PR, the conductor runs `unblock --startable`, starts each story it prints as `startable:`
(§ Merging), and runs `status`, acting only on its own stories: its epic's, or for the backlog conductor those with no epic. It tells each child
with a merge line to merge that ref, re-run the tests and push, first starting a builder in the
child's worktree when the line says `(no builder)`, and reviews the new head, since a review from
before the merge is stale. A merge line stays until the child pushes, so the conductor sends each
one once and skips it until the child's builder replies. It closes a lost ready child whose builder
is open with `paused`, which holds it for the lead. It lists for the lead a lost child that has no
builder or that close did not hold. `next` says
`auth` too when the conductor's login expired. A Claude agent's state comes from its own session in `claude agents --json`, read once per
run: busy is working, idle is idle, waiting is WAITING with what it waits for, and a recorded
session with no entry in the list (`gone`: the session ended) or no state in it (`unknown`, also
when there is no `claude` to ask) needs a look. herdr's word stands only for codex agents, agents
with no session recorded, and retired panes. `swarm.sh dash` shows the
same on one screen, for a person to scan: a summary line, then what needs the user first (PRs to
merge with their checks, `lead` stories, agents waiting on a prompt (with what their session waits for), agents whose session is gone or unknown, agents whose login expired, empty panes, stalled
agents), each active epic with a bar of its finished stories (finished story files are deleted,
so they are counted from history: a deletion counts once per slug, and only when it closed the story,
never a re-scope) and its live agents and open PRs beneath it,
and the recent events with how long ago; idle agents and blocked or later items are counts. One
status vocabulary runs through it (● working, ○ ready, ◐ review, ✓ done, ✗ failing, ⏸ blocked, ! needs you or a
session gone or unknown, ? a herdr state dash does not know).
`--tree` shows the agents by workspace and tab and `--ladder` the model per role; `dash --watch
[seconds]` redraws it in place until `q`, with `t` and `l` toggling the two. Both only read: they never change the board, the state or the logs, and never open
or close a pane, so `dash` asks herdr for the agents even outside a herdr pane.


The builder's brief is the story file plus the standing rules (never merge, no real cloud, the
codex loop through `swarm.sh codex-review <base>`, reply with the PR URL when CI is green, and keep any load it starts on purpose within 4 CPUs in all and remove it when the check ends), the epic's `check:` command when it has one
(the builder runs it before opening the PR), then the project's own rules from
`.claude/swarm/brief.md`, plus the tagged rule lines (`<!-- lesson: <kind> -->`) of the project's
`AGENTS.md`, `CLAUDE.md` and `.claude/CLAUDE.md`, since a builder in another repo's worktree reads
that repo's files, not this project's. `herdr agent read <slug> --source recent-unwrapped` shows what an agent
is doing.

**Review before closing.** A PR that changes only board files (no code) gets one
`swarm.sh codex-review` pass plus the lead's own reading, not repeated passes. A story is reviewed when its latest head has passed
codex and, on its first round when it changes code, the `/code-review` skill. The moment a story's PR head is green and
mergeable, the conductor starts a review agent for it with `swarm.sh review-agent <slug> <PR URL>`.
It does not wait for other PRs or reviews, and runs one for every green PR at once, so PRs that land
together are reviewed together. The command returns straight away, and records the head it reviews
in `.swarm/reviews/<slug>.head`. The agent, `review-<slug>`, is read-only and runs in the story's worktree and tab. It
runs `codex-review` with `SWARM_STORY=<slug>` and, on the story's first round when the PR changes
code, `/code-review <PR URL>`. From round 2 on it runs codex alone. `review-agent` counts the round
from the findings `tell` sent the builder since the story's last build started (a step-up or a
restarted builder does not start it again).
It judges the PR against the story's touches and **Done when**. A point that only a change to a file
outside the touches can fix is out of scope; a gap in the PR's own code is a finding, even where the
touches do not name it. One exception: a comment, doc or error-text line that the changed code no
longer matches is a finding at its `file:line`, even when its file is outside the touches. Its brief
carries the project's own rules, as a builder's does, and the checks the lead used to make by hand,
which the fallback reviewer's brief carries too. After them come the
lines of the story and its epic that hold a `(user, <date>)` mark. Each is printed as it stands, with
its `path:line`, cut at 1500 bytes on a character boundary, and the brief tells the reviewer to read
each decision in full at that line. Together they take at most 2000 bytes; past that, the brief says
how many were left out and which files hold them. A mark inside code or a fenced block, or in the
story's own **Done when** (which the brief already quotes), is not a decision. A PR that contradicts
a decision is a finding, even when the PR is stricter. The fallback reviewer gets the decisions
only when codex-review knows the story (`SWARM_STORY`). It writes to the absolute
path `<project>/.swarm/reviews/<slug>.md` (its working directory is the worktree, outside the
project), and replies with that path. It writes the file in one go once both reviews are done,
after `review-agent` has removed the one from an earlier head. The file starts with `head: <SHA>`,
the PR's head, which `review-agent` reads from `gh` and puts in the brief, then `codex skipped:
<why>` when codex was skipped. Under them go the findings,
each with its reviewer and file:line, then an out-of-scope section for points raised outside the
story.
`review-agent` refuses, starting nothing and leaving the last review's file in place, when the board has a story named
`review-<slug>` (whose builder would hold the same agent name), when the worktree is not at the PR's
head or has uncommitted changes, or when `review-<slug>` is still working or still open with no
findings file (idle while its codex runs, not finished). It moves the last review's file aside
before the new agent's brief goes, puts it back if herdr cannot start the agent, and deletes it once
the agent has started. When the start fails, `review-agent` first reads the error. If herdr may
have sent the brief (its reply could not be read, or the brief was sent and not taken up) and
`review-<slug>`'s session reads busy or waiting (herdr's working or blocked for codex), it says the
agent is running, records the head, keeps the file aside as `<slug>.md.prev` and exits 0; `wait
review-<slug>` then waits for a new file. If herdr may have sent the brief to an agent that is not
running, it keeps the file aside, records no head and fails, saying how to close the pane and start the
review again; so does a start whose agent herdr cannot list, since its state is unknown. In every
other case (herdr surely sent nothing, no pane, a session that is gone, or one herdr has no status
for), it closes the pane, puts back the file it moved unless a new findings file is already there,
and fails. A `.prev` an earlier start left, with no findings file since, stays where it is. For a story stacked on
parents, the brief names their branches: their code is in the diff against the base, but the agent
lists it neither as a finding nor as out of scope. The conductor waits on each review in the background
with `swarm.sh wait review-<slug>`. A review agent goes idle while its codex runs in the
background, so for an agent agents.tsv records as role `review`, that wait, like a conductor's,
holds on until the findings file exists, and fails if it times out without one. The conductor
then triages that story's file, and closes the review agent whatever
it found. A file with a `head moved:` line, or with no findings section, is not a pass: the
conductor starts the review again. When the wait returns with no file (a timeout, a prompt, a gone
session, an expired login), it closes the review agent without answering its prompt, and reviews
again or reads the diff itself. It sends the real findings to the story's builder with `swarm.sh tell <slug> findings
<file>`, and logs each out-of-scope item with `log-finding --declined out-of-scope --reviewer <who>`.
It starts a new review agent on the builder's next head. A round is one review whose findings went
to the builder; a review started again (head moved, no findings section, a review agent that timed
out or crashed) is not one. A review on the latest head whose findings are all declined is a pass,
never sent to the builder. Each declined finding is rebutted in the PR with a
reason and logged with `log-finding --declined <reason> --reviewer <who>`: `nit` for a nit, an edge
case or a low-value point, `out-of-scope` or `wrong` where they apply, and a point already declined
with the reason it was first declined with. Before a story merges or goes to review, it
compares the file's `head:` line with the PR's head, and reviews the new head when they differ. Once
a PR's latest head has passed, it merges it (or hands it over) at once, never holding the result
while other reviews run. A PR whose head has been green and mergeable for `queue_minutes` with no
review agent on that head is `queued`: `watch` returns `queued: <repo> #<n> <branch> green <m>m with no review on <sha>`,
and `next` prints the same line, naming the conductor, for the lead to send it (§ Settings, `queue_minutes`). `tell`'s kind (`findings`, `nudge`
or `resume`) is required and goes in the audit log. `tell` sends only to an idle session. It
refuses a builder that is still working, waiting on a prompt (it names what the prompt is), or whose
session is gone or unknown. herdr can read a pane idle through a whole turn, so a message or brief
(a `tell`, or a start's brief) counts as taken when the agent's own Claude session shows it, too: the
session reads busy or waiting, or its log has the message as a new prompt (for a `tell`, the file's
first line). When the session read idle before the send and shows no sign of it, the message goes
once more, and the command fails if it still shows nothing. With no session to read (codex, a session
Claude Code does not list yet, or one it reads busy or not at all), a message herdr sent is never
sent again: when herdr shows no turn, the command succeeds and warns that herdr sent it the brief and
did not show the turn start. To reach a busy conductor, the lead runs
`swarm.sh tell conduct-<epic> note <file>`. It appends the file under a timestamped header to
`.swarm/inbox/conduct-<epic>.md`, and only for a live conductor of this project. A conductor
whose turn has ended (idle, or busy only with background jobs, as `upgrade` reads it) also gets a
short prompt telling it to process its inbox now, by the steps below, run `swarm.sh unblock
--startable <epic>` (or `--backlog`) and start what it prints, then end its turn, leaving any wait or
watch it has running alone (it starts one only if none runs). A wait can run a long time before it
returns. `tell` sends the prompt once and returns without waiting for it to be taken up. One
conductor gets at most one such prompt a minute: `.swarm/inbox/conduct-<epic>.woke` holds the last
one's time, set under `conduct-<epic>.lock` so of two notes at once one sends it (a lock left over a
minute is cleared; one held past 5 s is warned of). A note also leaves one check pending in the
background (`conduct-<epic>.later`): once the minute since the last prompt is up, it prompts the
conductor that holds the name then, if the inbox is still there and no prompt went out meanwhile. A
prompt sent while the check waits moves the check once, to the end of that prompt's minute. So a
burst of notes sends one prompt now and one a minute later, and a prompt that was dropped, or
answered without reading the inbox, is sent once more. A prompt that fails is warned of and its time
taken back, so the next note tries again. No prompt goes to a conductor mid-turn, one that has
written its report, or one that `upgrade` asked for a handover and has not yet told to carry on
(`conduct-<epic>.upgrade`, which upgrade touches each round and which is ignored once an hour old). After each `wait` or `watch` returns, the
conductor moves the inbox with `mv` to `conduct-<epic>.reading.md` beside it (so a note added
meanwhile starts a new file), reads that copy, acts on it and deletes it. A copy already there is a read that was cut off,
so the conductor reads and deletes it first. It does all of this once more just before it writes its
report, so a note left after its last wait is still read. Once a new conductor has started,
`conduct` clears both files, and the `.woke`, `.later` and `.upgrade` beside them, so it never acts on notes left for the one before. A `conduct` refused
because the epic's conductor is still running leaves them alone. The conductor closes a builder only after both
reviews pass, so the fixes are made by the agent that wrote the code, with its context. A pass
that finds only nits, edge cases outside the story, or points already declined counts as passing: a
reviewer built to find edge cases never comes back empty, so waiting for an empty pass never ends. Each builder
also proves its tests can fail: it breaks its fix, watches a test fail, and restores the fix.

Every codex review a builder, a conductor or the lead runs goes through `swarm.sh codex-review
<base>`, in the worktree, with `SWARM_PROJECT` set to the project so a worktree of another repo still
reads its config. It runs `codex exec review --base origin/<base>` with no prompt (codex refuses one
beside `--base`) and stdin from `/dev/null`, and stops it after `codex_minutes`. With
`SWARM_STORY=<slug>` it passes a prompt in place of `--base`. The prompt asks codex to review the diff
against `origin/<base>`, uncommitted changes and untracked files included, so a builder's review
before its first commit sees its work. It lists the story's touches with its **Done when** and **From review** items,
and holds out of scope only a point that a change to a file outside the touches alone can fix. If `SWARM_STORY` is not a slug, names no story file,
or names a story with no **Done when** item, codex-review fails before codex starts. An interrupted
codex-review stops codex the same way and exits only once it is gone. While it runs it keeps a marker,
`.swarm/state/codex-review.<pid>` (start time, base, worktree), which the dash reads for its codex
row. It removes its marker when it exits, and on start removes any marker whose process has died. codex stays in the caller's
process group, so a harness that kills that group kills codex too. On macOS a KILL to the group can
miss a child that codex forks while the KILL is sent, so a harness that must leave nothing STOPs the
group first. Every brief says to run it in the
background (Bash `run_in_background`) and wait for it: Claude Code stops a foreground Bash call at 2
minutes by default and 10 at most, before the limit could apply. Whoever runs it waits for it to
exit and acts on what it prints last, since a usage limit printed early may be followed by a
fallback's review. When it ends on codex's usage limit or on `codex skipped: ...`, no one runs it again: a
builder carries on, the conductor or the lead reviews the diff itself, and the PR says `codex
skipped: usage limit` or `codex skipped: timed out`. A review agent says `codex skipped: <why>` in
its reply, and the conductor then reads the diff itself in codex's place. codex-review sends codex's
output, stderr merged into stdout, to the screen and to a log in a temp directory of its own (mode
700, so no other user can make or read it first), removed when it exits. Once codex exits,
it waits a few seconds for the output to finish, and on any way out (the timeout and an interrupt
too) it stops the copy, so a child of codex left holding the output cannot hang the caller. If codex fails and its last lines hold its own limit message (`You’ve hit your usage limit`, with
`ERROR:` or `■` before it; a review that only quotes the words does not count), codex-review logs a
`codex-limit` incident in events.tsv, with `codex-<story>` as its target (not the slug, which is the
builder's own agent name). With `fallback_reviewer` empty it then exits as codex did. With
it set, it starts `fallback-<story>` in the worktree on that model, with codex's prompt. The agent
runs with no Edit, Write or NotebookEdit tool and cannot commit or push. It still has Bash, so
unlike codex's read-only sandbox its brief is what keeps it from changing the worktree. It gets what is left of `codex_minutes`, its start included, so the whole run stays within it, to write its
findings to `.swarm/reviews/fallback/<story>.md`, in a tab of its own (`fallback-<story>`). codex-review prints `reviewed by fallback <model>:
codex usage limit` and then the findings, and closes the agent, findings or not; an interrupt closes
it too. The builder treats the findings as codex's, logs them with `--reviewer fallback`, and the PR
body carries that line instead of `codex skipped`. When the agent cannot start (outside herdr,
start_agent refusing, or its name, cut to 32 characters, held by another story's fallback) or writes
nothing in time, codex-review prints `codex skipped: usage limit (<why>)` and exits as codex did. It
waits for the file, not for the agent to go idle: an agent idle while a subagent or a background
call of its own runs has not finished. With
under two minutes of `codex_minutes` left, no fallback starts: it prints `codex skipped: usage limit
(no time left for a fallback)`. The planning `codex` panes of
`/plan-epic` are not run this way: `wait`'s timeout bounds them, and the lead closes them.


## Logs and outcomes

**The audit log.** Every `swarm.sh` command appends one line to `.swarm/events.tsv`: the time,
the command, its target, the herdr pane that ran it, and how it ended: `ok`, `interrupted`, the first
line of the error that stopped it, or `failed (exit N)` when the error came from a nested step, whose
message a caller may have handled (it still reaches the terminal). Only the read-only commands are
exempt (`READ_ONLY_COMMANDS` in `bin/swarm.sh`: `dash`, `status`, `next`, `config`, `policy`,
`cost`, `outcomes`, `flow`, `dataset`, `review-yield`, `features`, `lessons`, `findings`, the `wait`, `wait-pr` and `watch` that conductors and the lead run all the time, `base`, and
`tidy` without `--yes`), so a new command is logged until someone names it read-only. The one
exception is `wait`, which logs each nudge it sends as `nudge <agent>` and each API-error resume as
`resume <agent>`. The stall rule skips those lines, because neither is a sign of life. Something that went wrong is an `incident` line,
its outcome `<kind>: <detail>`, which `flow`'s `incidents` section counts. `wait` writes two kinds:
`wait-timeout` when its wait runs out (not when herdr's wait fails sooner, and not for a
`wait --until-report` hour that it waits again), and `login` when it returns `auth`, once per
expired login: a second wait adds none, and a `tell` (the resume after the `/login`) starts a new
one. A `close` that ends a build with no open or merged PR on `story/<slug>` writes `idle-no-pr`,
unless its cause is `stalled`, `paused`, `cleared-on-error` or `impossible`; the waits on that builder write
none, so one stuck builder is one incident. `swarm.sh intervene <kind> "<one line>"` writes one with
target `-` and the outcome `<kind>: <line>`, for each time a person had to step in: `lead-hand`
when the lead did by hand what a command should have, `user-caught` when the user found a problem
first. Any other kind, or an empty line, fails and writes nothing, and so does an events.tsv it cannot write. When `status` or `wait` reads an agent's pane, herdr
says its turn ended (idle or done), and the turn ended on an `API Error:` line or on the tool result
Claude Code gives for a denial (`Error: Permission for this action was denied by the Claude Code auto
mode classifier.`), it writes `api-error` or `auto-denied` with that line, once per stop. An `API
Error:` line counts only after `⏺` or `●` at the margin, where Claude Code prints its own. An agent's
own indented text does not count, and neither does a tool's output (`⎿`) that prints `API Error:` or
quotes the denial. `next` and `tell`
only read. `status` and `wait` keep `.swarm/panes/<agent>`: the pane's checksum, when they last saw it
change (which `dash` shows), and which stop was logged last. Stops are told apart by the lines from
the last prompt above the stop down to it, or by the stop's line alone once that prompt has scrolled
out of the window.
The record drops it when a read of the pane shows no stop. Reading the same stopped pane again, after
it scrolls or after a resume it has not shown yet, adds nothing. A stop after a new prompt is a new
one, even when the resume and the second error both come between two reads. A retired agent's record moves to its new name, and a new
agent of the name starts with none. The stall rule skips incident lines as it skips nudges and resumes. A `tell` is logged as `tell:<kind>` with the slug as
its target, or as plain `tell` when the kind is missing or wrong. One that reached the builder counts as a swarm action on the story. The stall rule
skips `tell:nudge`, since it is a nudge too, and any tell that ended other than `ok`, since it never
reached the builder. It also skips `tell:note`: a note the lead leaves a conductor says nothing about
whether the conductor is working. A `close` with a cause is logged the same way, as `close:<cause>`, and one with
no cause as plain `close`. A close with an unknown cause is refused and logged as plain `close`,
and the word that was given never reaches the log. `reconcile` and `unblock` write a line
per item they move. `merge` writes all its own lines, under the story's or epic's slug (the PR URL
with `--board`, or before it knows the item): a refusal is one `merge` line saying why, and nothing
else; a PR that `gh pr merge` ran on but that never reads as merged is one `merge unconfirmed
(<state>)` line; otherwise `merge ok`, then `main-ci` with `ok`, `red <checks>`, `timeout (<what it waited on>)`
or `error <why>` (a red one followed by `main-red`, target the merge commit, outcome its repo, base and checks;
an ok one that clears a red main of that repo and base by `main-green`, outcome its repo, base and
the red commit it clears, and a `fix-main` line,
outcome `retired: <why>`, for each unstarted fix-main story that retires), then reconcile's lines. Before an ok `main-ci` comes a `flake` line for each run whose rerun went green, outcome `<jobs> <run URL>: <FAIL lines>`, a record that no command reads yet. Through a merge queue (§ Merging) it is the same `merge ok`,
`main-ci` and reconcile lines, or a single line: `merge dequeued (<reason>): <checks>`, `merge closed while
queued`, `merge the head is <sha>, not <sha>, the head that was checked; ...`, `merge gh pr merge
--auto failed: <error>`, `merge could not read whether <base> has a merge queue: <error>`, or `merge
unconfirmed (<why>)` for a timeout (`timeout (<what it waited on>)`), an error, a PR never read as
queued, or a merge with no merge commit. A merge at a head other than the checked one is `merge
merged at head <sha>, not <sha>, ...` and then reconcile's lines. A `story` that starts an `escalate` build, and the `close` that hands its story to
the lead, each write one more line of their own (§ Model and effort). The plugin's merge guard
(§ Merging) writes an `incident` line, target `-` and outcome `merge-blocked: <form>` or `guard-blocked: <form>`, for each call it blocks.
`reconcile` writes one, target `-` and outcome `pull-failed: <files>`, when changed tracked files stop
its pull (§ Merging), once while the same stop lasts, and one with outcome
`key-dropped: <file> <key>: <yours> -> <theirs>` for each uncommitted `status` or `prs` its pull replaced. The log is local to the machine and append-only,
holds names and paths but never a brief's or a message's contents, and a write that fails never
fails the command. The outcome field is the one place free text gets in: the reason given to a
`reset` or `drop`, the answer given to `dialog`, the PR URLs a `review` names (`ok (<PR URLs>)`),
and the first line of a failed command's error.

`swarm.sh outcomes [--since YYYY-MM-DD]` joins the logs per build. It prints one TSV row for each
builder in `.swarm/agents.tsv` with the story's slug, kind and risk, the model and effort, the cost
and tokens from the session's own log, the tells it took by kind (`tells_findings`, `tells_nudge`, `tells_resume`; a bare `tell` from older logs counts as findings, and a refused tell, which never reached it, is not counted) and its `close` lines in this log (any cause), the findings logged
against its PR, the PR and its state from `gh`, and which attempt at the story it was. Then come
`started` (the first timestamp in the session log, in UTC, or empty with no log), the tokens by type
(`tokens_input`, `tokens_cache_write`, `tokens_cache_read` and `tokens_output`, which add up to
`tokens`), `close_cause` (the cause on the build's last close, empty for a plain `close`), and when
each escalation step was logged: `escalate_at`, `dialog_at` with `dialog` (`accepted` or `dismissed`,
otherwise empty), `escalated_at`, `reset_at` and `drop_at`. The reason given to a reset or drop is
never printed. After those: `epic` (the story's `epic:`), `merged_at` (when the build's PR merged),
`story_merged` (`true` on every row of a story when any of its PRs merged, `false` when `gh` found
none merged, and empty when that is unknown: the story is gone, it names no repo here, or `gh`
failed), `findings_declined`, and `findings_fixed_by` and `findings_declined_by`, which count each by
reviewer as `<reviewer>:<n>` pairs in name order (`unknown` for rows logged before the reviewer
column). Four more columns come from `gh`: `pr_created_at` (UTC), `start_to_pr_min` (minutes from
`started` to `pr_created_at`, empty when the build started after its PR already existed, as a retry
does), `pr_to_merge_min` (minutes from `pr_created_at` to `merged_at`), and `main_merges`, the
commits on the PR whose headline merges the base branch into it (`Merge origin/main into …`,
`Merge branch 'main' into …`, `Merge remote-tracking branch 'origin/main' into …`). Each is empty
when its inputs are. `pr_created_at`, `pr_to_merge_min` and `main_merges` describe the PR, not the
build, so they repeat on every build that shares it: count a retried PR once when you sum or average them. Last
come `subagent_cost_usd`, the estimated cost of the builder's subagents, `subagent_cost_by_model`,
the same cost split by model as `<model>:<usd>` pairs joined by commas (`haiku:1.00,opus:2.00`, with
`other` for a model that has no price), and
`subagent_tokens`, their tokens of every type. A
subagent turn is one with `parent_tool_use_id` or `isSidechain` set in the builder's session log, or any
turn in the `subagents/*.jsonl` logs in the folder named after the session, next to its log. `cost_usd`
and the tokens columns count the builder's own turns only, so `cost_usd` plus `subagent_cost_usd` is
the whole build. The subagent columns are empty when there is no session log. When only the copy
`close` keeps of a deleted log is left, they count the subagent turns inside that log alone: the copy
leaves out the `subagents/` logs beside it. After them come five columns that split the minutes
from `started` to `merged_at` into phases: `building_min`, `ci_min` (a check
on the PR's head was running), `review_wait_min` (from `pr_created_at` to the first `review`
event after it, which hands the PR to the merger, or to the merge), `fixing_min` (from each
`tell:findings` logged between `pr_created_at` and the merge to whichever comes first: the PR's
next commit (a commit that merges the base in does not count), the next check start, `review` or
`tell:findings` event, or the merge) and
`merge_wait_min` (from that first `review` event to the merge). A `review` event, of the story or
of its epic (`swarm.sh review <epic> <PRs>`), counts for the PRs it names in its outcome. One logged
before reviews named their PRs (a bare `ok`) counts for its story's PR when exactly one was open then. Where two phases cover the same
minute, the higher one takes it: fixing, then CI, then review wait, then merge wait; a minute none
covers is building. The five add up to the whole minutes from `started` to `merged_at`, and are
empty when either is missing. The events are those of every build of the story, so a retry's tells
count in the first build's minutes too, and the first build's in the retry's; a tell on an earlier,
abandoned PR is not counted, as it came before this PR was created. `gh` gives only the latest run of
each check on the PR's last head, so other CI counts as whichever phase lies under it. A check cancelled while
queued, which `gh` dates to the year 1, adds no CI. The four after `building_min` cover a PR's time
in review, from `pr_created_at` to the merge, so they add up to `pr_to_merge_min`. Next comes
`rework`: 1 when a later fix reworked the build's merged PR and 0 when none did, as defined under `flow`'s `model_fit` section
(below). Any PR merged in the repo can be the fix, whether or not a build made it: `outcomes` lists
the repo's merged PRs once with `gh`, from the first merge day of the builds it judges to 8 days after
the last (`gh` dates in UTC, and a local 7th day can be the next day in UTC). It judges the PRs merged
from 7 days before `--since` on (`flow`'s `--since`, when `flow` runs it), so a 1 shows as soon as a fix
merges, while a 0 waits until 7 days after the merge. The cell is empty on a PR that never merged, on an
earlier build that shares the PR (so a reworked PR counts once), on a PR merged 7 days ago or less with
no fix yet, and where rework is unknown: a PR merged before that window, every PR when `gh` failed, and
a PR merged before the oldest PR of a `gh` list that came back 1000 long, whose fix the list may have
missed. A line on stderr names each of the last two cases. `outcomes` alone
computes rework; `flow`'s `model_fit` and `reviewers` sections read this column. The last column,
`held_min`, is on a story's first build alone: the minutes it sat ready and unstarted under the
conductor run the build started in, counted from the later of the run's start and the story's ready
time. The conductor is its epic's, or the backlog conductor (`conduct --backlog`) for a story with
no epic. The story became ready at its last `ok` `unblock` event, or commit on the board's default
branch that set its `status: ready` (a story added ready, or readied by hand), before the build. A
commit that set it `status: blocked` after that leaves no ready time. A run starts at an `ok`
`conduct` event and ends at the next one, at an `ok` close of the conductor, or when it wrote its
report, whichever comes first. The report's time is its file's (`.swarm/conduct-<epic>.report.md`)
until the next `conduct` removes the file; that `conduct` logs it first as a `report <epic>` line in
events.tsv, `ok (<UTC time>)`. A build that started after its run ended, or with no run, held 0.
`held_min` is empty when the build has no `started` or the story has no ready time by then, and on a
retry, whose own wait is not counted. After it, `ready_wait_min`, also on a first build alone, is the
whole wait from that ready time to the build's start, with or without a conductor running. A story
with no ready signal before its build started (it was readied only after) waited 0. Otherwise it is
empty where `held_min` is for want of a ready time. A step-up rung keeps attempts at 1, so it carries
its own `held_min` and `ready_wait_min`, timed to its own start; `flow`'s `time_in_state` counts each
story once, by its earliest build. A story the lead holds after an escalation (`kind: lead` with
`escalated_from:`) shows the kind it was built as. New columns only ever go on the end, so
`flow`, which reads them by name, and anything that cuts columns by position keep
working. The slug comes
from the session's worktree, because agents.tsv cuts names at 32 characters. Each build gets its own
PR: the last of the story's PRs that its session log names, so a retried story shows the first build's
closed PR beside the retry's merged one. A build whose log names none of them has no PR, and a build
with no log left gets the story's PR only when it has exactly one. A story that merged and
left the board is read from git history. If `gh` fails, the PR columns stay empty. Each finding counts
for one build: the latest build on its PR that started on or before the day it was logged, so a
retry that reuses a PR doesn't count the first build's findings again. It writes nothing.

After the rows and a blank line, `outcomes` lists the finding kinds that keep coming back: every kind
fixed (or escaped) on 3 or more distinct PRs in the last 30 days, today included, most PRs first, as
TSV with the columns `recurring prs_30d check check_merged before_30d since_30d`. A declined finding
does not count, and neither does a row whose date is impossible or in the future. Once a story that
names the kind in its front matter (`checks: <kind>`) has merged, which means it was deleted on the
default branch (`origin/HEAD`, or `HEAD` when there is none) and git still has it, `check` is its
slug and `check_merged` is the day of the commit on that branch that deleted it (the merge commit,
for a merged branch). `before_30d` is how many PRs the kind was fixed on in the 30 days before that
day, and `since_30d` the same for the 30 days from it, so you can see whether the check helped. Until
30 days have passed, `since_30d` reads `<n>/<days>d`, the days it covers so far: `1/3d` three days
after the merge is too soon to judge. With nothing recurring, the block is left out. `flow` and `review-yield` skip these lines.

Each `events.tsv` line counts for one build, so a retried story's tells and closes are split among
its builds. A line whose time does not parse counts for none. An escalation step goes by the order of the log. Each `escalate` opens a cycle for the
story's next escalate build in agents.tsv that has none yet. A later escalate build takes the cycle
instead when its session log started nearer this `escalate` than any other of the story's, and nearer
than that first build. So a build whose brief was never taken up (it logged no `escalate`) cannot take
its retry's cycle, and a build whose log is gone keeps its own. The cycle runs until the
story's next `reset`, `drop` or `escalate`, and every step logged in between belongs to that build.
If a step repeats in one cycle, the last one counts. A tell or close goes to the story's build that started last at or before it. A build whose
session log is gone starts at 00:00 local time on its agents.tsv day, converted to UTC.


`swarm.sh close` keeps the Claude session log of each agent it closes (every agent in a tab it closes), because Claude Code deletes those after
`cleanupPeriodDays` (30 by default) and they hold every tool call and the model of every turn. The log
is copied, gzip'd, to `.swarm/sessions/<date>-<agent>-<session>.jsonl.gz`, once per session; a codex
agent has none to keep, and neither has an agent whose name runs past 32 characters: `agents.tsv` keeps
only the cut name, whose newest session may be another agent's that is still running. Nothing is redacted, because a list of what to scrub misses whatever it
doesn't list, so the copy holds whatever the session held. The copy is readable by its owner only,
and `.swarm/` is git-ignored: the archive stays on the machine, and is never committed or uploaded.
Flow's `cost` section and `outcomes` read a session's live log while it exists and this copy once
Claude Code has deleted it, matching the copy on its session id, so their tokens, cost and slugs
outlast the 30 days. The stall rule, the goal check and `dash` never read the copy: an archive is
no sign that an agent is alive.

## Flow and features

`swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>] [--no-cache]` prints the project's
numbers in sections, one per `bin/lib/flow_<name>.py` in name order, each under a `## <name>` line:
`ci_health`, `cost`, `epic_totals`, `features`, `gh_calls`, `holds`, `idle_slots`, `incidents`, `lead_queue`, `merge_ins`, `merges`, `model_fit`, `predictions`, `review_loops`, `reviewers`, `test_runs`, `throughput` and `time_in_state`. Each section gets the window (`--since` and
`--until`, which must be real dates, and `--epic`), the log paths and the `outcomes` rows, and calls
`gh` itself if it needs to. A new section is a new file, so adding one changes neither `flow` nor
the others. `flow` writes nothing but its own gh calls' lines in `.swarm/gh-calls.tsv` and its cache (below), except that `merge_ins` may fetch a PR's head into its repo, and its `git merge-tree` writes the trees and blobs of each re-merge into the repo's object store. For one release, the old `cost`, `features` and `review-yield`
commands still run, and each prints which section now holds its numbers.

GitHub history that is finished never changes, so `flow` (and dash's ci refresh, which runs it)
reads it from `gh` once and keeps it in `.swarm/gh-cache/<owner>--<repo>/` (`bin/lib/gh_cache.py`),
one JSON file per record: a merged PR; a closed PR's commits and runs, once `gh` lists some runs and
none of them is still running; a completed run's jobs and earlier attempts; the `FAIL` and `TIMEOUT`
lines of a red attempt's log (never the whole log, and never an empty answer, which comes back while
GitHub is still archiving a log); a PR's `createdAt` and branch; the merged PRs `rework` searches,
for the last 120 days; and the repo's completed runs that the flaky tests read, for the last 90 days
(each kept for the window, if longer). An open PR and a run still in progress are read fresh every time. A closed PR that was not
merged can be reopened, so it is read again every time, and its commits and runs are read again
once its `updated_at` moves; records kept under an earlier `updated_at` are deleted then.

The two listings ask `gh` for the window while nothing is cached, then only for what is new, and the
window is served from the cache. Merged PRs are searched from a day before the newest cached one's
day, because GitHub's search can list a merge late. Runs are listed from three days before the
newest cached one's day, or from the oldest day with a run still running (a run queued for over a
day holds nothing), or from the window's start when that is later. A run listed again while a rerun
of it is running is dropped until the rerun ends. A rerun keeps its run's creation time, so a rerun
of a run created more than three days before the newest cached day is not seen. A runs listing
that GitHub cuts at 1000 (the newest) is listed again up to the oldest day it reached, until it is
whole; only a single day of more than 1000 runs is left out. What a cut listing leaves out (the
merged PRs before a cut list's oldest, or such a day of runs) is kept as the cache's hole, listed
again first on every run whose window reaches it, and every such run that finds it still cut says
so: a `flaky tests:` line, or `rework` unknown for the PRs merged before the cutoff. A file is written to a
temp file and renamed, so a parallel `flow` never reads half of one; one that cannot be read or
parsed is read from `gh` again and rewritten, and one that would not change is not written.
`--no-cache` reads nothing from the cache, `.swarm/outcomes-prs.tsv` included, and writes what `gh`
answers over it, so it also shows a rerun the cache missed. Setting `SWARM_GH_CACHE` empty turns the
cache off (the tests whose `gh` stub changes between runs do).

The `ci_health` section prints one TSV row, `prs heads ci_min_median red_runs_per_pr flakes`, over
the github.com PRs of the `outcomes` rows dated in the window (with `--epic`, that epic's); a PR
elsewhere, such as GitHub Enterprise, is left out. Each PR costs three or more `gh` calls, so without
`--since` the window is the 30 days up to `--until` (or today), and a line above the row says so. For each PR, `gh` gives its commits and its
branch's completed workflow runs, and a run counts when its head is one of those commits. `ci_min_median` is the median, over head SHAs, of the minutes from a head's first run
created to its last run updated. `red_runs_per_pr` is the red runs (a failure, a timeout or a run that could not
start; a cancelled or skipped run is not red) over the PRs. `flakes` counts each red run followed by a green one of the
same workflow and event on the same head, so a workflow red on push and green on pull_request is no
flake. `gh run list` shows only a rerun's last attempt, so the section reads each earlier attempt's
conclusion from `gh api`. A run whose times do not parse adds no minutes. It reads each PR over gh's REST API, whose hourly limit is separate from the GraphQL one a swarm's `gh pr` commands spend. A reset connection or a 5xx is tried three times, 1 and then 2 seconds apart. Any other error is not tried again, and after `API rate limit exceeded` the section makes no more `gh` calls. A PR that `gh` cannot read, or whose call takes over 10 seconds, is left out of the row. A line under the row says how many, and a `ci health: left out <PR>: <the gh call>: <gh's last line of error>` line names each one. The ci time table below does the same with `ci time:` lines.

After the ci time table, so its reads never starve that table, a `test_file flaky_runs last_seen example_run` table names the test files that
fail and then pass on the same commit, worst first. It lists the runs created in the window, one
`gh api` call over GitHub's UTC days, in the repos of the window's PRs (one `gh` could not read
too) and in the project's origin, so runs on main and on the lead's own PRs count too. With `--epic`, it reads only that epic's
PRs' runs. A flaky run is the one `flakes` counts: a red attempt that a green one on the same head,
workflow and event follows, in the same run or a later one. For each one, `gh run view --log-failed`
gives its red attempts' failed steps, and each of `scripts/test.sh`'s own lines for a failed file,
right after the log's `<job> <step> <timestamp>` prefix
(`FAIL tests/<file> <n>s`, `FAIL tests/<file>: its job ended without a result` or `TIMEOUT
tests/<file> after <n>s`) counts that file once for the run; a test's output that quotes, indents or diffs such a line
does not. `last_seen` is the day the file's latest flaky run was created,
and `example_run` links that run's attempt. It reuses the attempts the row already read, reads the
newest runs first, makes at most 100 `gh` invocations (not REST requests: the listing pages up to 10,
a log download takes several, and a 5xx is tried up to 3 times), and stops at `API rate limit
exceeded`, keeping what it read; a `flaky tests: stopped at` line names the repos it did not list
and how many runs it left. Lines starting `flaky tests:` also say when GitHub listed fewer runs than the window has (it
lists at most 1000), name each run or log `gh` could not read, count flaky runs whose logs have no
such line among those whose logs were read (`go test` or `pytest` output, say), and print `none in
the <n> runs read` (each run once) when every listing was read in full, nothing stopped, and
nothing was flaky.

The `cost` section shows where the tokens went: tokens and estimated cost per role for the agents
started in the window, with a `lead` row for your own sessions (by their first timestamp's local
day). With `--epic` it still counts every agent in the window, and says so.

The `epic_totals` section prints one TSV row per epic and a last `all` row, over the `outcomes` rows
dated in the window. With `--epic` it prints that epic's row alone. Each row sums `cost_usd` and
`start_to_pr_min` over its builds. It counts each PR once, however many builds share it:
`pr_to_merge_min` is summed per PR, `merged_prs` is the merged PRs whose `main_merges` `gh` could
read, `main_merged` is how many of those had main merged in, and `main_merged_share` is that
percentage. An open or abandoned PR is left out of the share, as it was from leaner-faster-swarm's
baseline of 55%, which a line after the table gives to compare against. `cost_usd` says how many
builds have no cost (no session log, or a codex agent), as `cost` does: `4.25 (1 not in the logs)`.
The minutes sums skip empty cells: `outcomes` leaves `start_to_pr_min` empty for a retry that started
after its PR was created and for a build with no PR.

The `merge_ins` section says why the PRs that `epic_totals` counts under `main_merged` merged their base
in: the PRs of the window's outcomes rows (or `--epic`'s), one row per PR, that merged with
`main_merges` above 0. With neither `--since` nor `--epic` it reads the 30 days up to `--until` (or
today), as each PR costs two `gh` calls, and a line says so. It reads each PR and its commits over gh's
REST API, with `ci_health`'s retries and its stop once the hourly limit is spent. A merge-in is a commit
whose headline merges the base in, the same rule `main_merges` counts by. `git merge-tree` re-merges the
commit's two parents in its story's repo (its `repo:`, or the project). When the commit is not there and
the repo's origin is the PR's repo, the section fetches the PR's `refs/pull/<n>/head` from origin once,
and a `merge ins: fetched` line says so. Every git call it makes runs as `dataset`'s fetch does: with no
prompt, ssh in batch mode, and a 60-second limit. A merge that conflicts is `conflict`. So is one git
merges clean but whose commit differs from that clean merge on a path the PR changes, a fix made by hand
before committing; a difference on other paths comes from another merge strategy (GitHub's "Update
branch", an older git) and counts as clean. A clean merge is `behind` when the base had commits the
branch lacked, and `neither` when it had none. `unread` counts a PR `gh` cannot read or whose answer
names no base branch, the merge-ins `main_merges` counted that `gh` does not list, a sha that is not 40
hex digits, a commit git cannot find, a merge-in whose `git log`, `merge-tree`, `diff` or `merge-base`
fails or runs out of time, and a "merge" with one parent (a squash or a rebase); a `merge ins: left out
<PR>: <why>` line names each. It prints TSV `cause merge_ins prs`, a row per cause (a PR with merge-ins
of two causes counts in both), then `file conflicts`, the three files conflicts and hand fixes hit most
(control characters dropped from the names); or `none conflicted`, or `none read` when it read no
merge-in.
The `gh_calls` section shows how the swarm spends GitHub's two hourly budgets (5000 GraphQL points
and 5000 REST requests). swarm.sh puts `bin/gh-shim` first on its own PATH and on every agent's, a
restored agent's too. The lead's own gh calls outside swarm.sh, and a person's, do not go through it
and are not counted. The shim runs the real `gh` with the same arguments, stdin and exit code (an
INT ends it and exits 130, as an interrupted gh would), then appends a line to the project's
`.swarm/gh-calls.tsv`: the UTC time; the agent (its name, or `-` outside any agent); the via
(`swarm.sh <command>` when swarm.sh made the call, a builder's `swarm.sh wait-pr` among them, else
`-`; the outermost command's, so what a command runs through another swarm.sh, such as `dash
--check`'s status or `merge`'s wait, counts as the command that caused it, while an agent's own
swarm.sh starts afresh); the subcommand (`pr view`, `api graphql`, or `api <path>` with the query
and any host cut off and each path segment that holds a digit shown as `:id`, flags before either
word skipped); the budget (`graphql` for `api graphql`, `status`, `label list` and the `pr` (except
`pr diff`), `issue`, `repo` and `project` groups; `none` for a run that spends neither budget:
`config`, `alias`, `completion`, `browse`, `help`, `--version`, any `--help`, a bare `gh`, `auth
token`, `auth git-credential`, `auth setup-git`, `api rate_limit` and `search`, which has a limit of
its own; `rest` for everything else); `many` (`paginate` for `--paginate`, `watch` for `--watch` and
`run watch`, else `-`); and the exit code. It logs nothing past the subcommand and API path, so
never a token, body or header, and a log it cannot write never fails the call. The read-only
commands (`dash`, `wait-pr`, `watch` and the others) log their gh calls there too; it is the one
file they write under `.swarm`. A row counts gh runs, not API requests: a `many` run spends several
requests, and a GraphQL query costs a point or more, so the share is a floor. The section prints a
line saying so, and that role `-` is a call outside any agent and share `-` a `none` run; then TSV
`hour api role runs many share`: for each local hour in the window and budget, an `(all)` row, then
one row per role (the agent's `agents.tsv` role; an agent it does not name as itself; `-` outside
any agent), most runs first, with how many were `many` runs and the share of the 5000 (`<0.1%` below
that, and `-` for `none`). After a blank line it prints the same per subcommand, `via swarm.sh
<command>` added when swarm.sh ran it. With no log yet, or no lines in the window, it prints a line
that says which. The section reads the log from the end and stops two days before `--since`. The
shim keeps the log from growing without end: about one call in 1000 counts its lines, and past
50,000 keeps the newest 50,000. GitHub's hour starts at a budget's first call, not on the clock, so
one hour here can straddle two of GitHub's. `--epic` does not narrow it.
The `incidents` section prints TSV `day kind incidents`: the `incident` lines in events.tsv
(§ Logs and outcomes) counted per local day in the window and per kind, whatever the kind, one row
for each pair with any. An incident's target is an agent name, which can be cut short of its slug,
so `--epic` does not narrow it. After a blank line, TSV `epic kind stops` counts the `api-error`
and `auto-denied` lines per epic: a builder's or `review-<slug>`'s epic is its story's, a
`conduct-<epic>`'s its epic, as `outcomes` gives them, and `-` when none does. `--epic` keeps that
epic's rows.

The `model_fit` section sets cost against results. It prints one TSV row per model and effort
crossed with a story class, over the stories whose first build is dated in the window (with
`--epic`, that epic's). A story counts under the model and effort of its first build, so a story
escalated to Fable stays under the model it started on, while its cost, attempts and findings
include every build. The class is the story's `kind`, `risk`, a size bucket from `estimate_lines`
(`<=100`, `<=300`, `>300`, or `none`) and the area most of its `touches` files are in: each file's
top-level folder, such as `bin/` or `src/`, or `root` for a file at the project's root (on a tie,
the first one named). Touches split as the
overlap check splits them, so `bin/lib/build.sh:f, g` names one file, a bare name such as `Makefile`
is a file when the project has one, and a note in parentheses names none. Each story is read from the board or
from git history, so merged stories keep their class. The columns are:

- `stories`, the stories built;
- `cost_per_merged_usd`, the cost of all their builds, subagents included, over the stories that merged, ending `(N not in the logs)` for builds with no cost, as in `epic_totals`;
- `first_attempt_merge_rate`, the share that merged on their only build, out of those whose merge
  `gh` could read, leaving out a story still in flight (no merge, an open PR); `-` when none is left;
- `mean_attempts`, builds per story;
- `findings_per_pr`, findings fixed (declined ones left out) over their PRs;
- `rework`, the stories with a merged PR that a later PR fixed within 7 days;
- `escaped`, the escaped findings on their PRs;
- `start_to_merge_min`, the mean minutes from the first build's start to the merge.

A PR is rework when a PR merged after it, on its merge day or up to 7 days later, says it fixes it,
or when a `log-finding --reviewer escaped` row dated up to 7 days after its merge day points at it.
Both count calendar days from the merge day in local time, as `findings.tsv` dates its rows. Saying so
means a fix verb (`fix`, `fixes`, `fixed`, `fixing`, `hotfix`, `bugfix` or `quickfix`), `rework of`
or `regression from` in the title or body, then the PR within 40 characters in the same clause
(clauses end at a sentence end, a `;` or a line break): its URL, `owner/repo#N`, or `#N` from the
same repo. A clause with `merge after`, `depends on`, `stacked on` or `merged origin/main` names a
PR without fixing it. Each reference is judged by the nearest fix verb before it, and a negation
directly before that verb (`doesn't fix`, `not fixing`, `never fixed`) cancels it, so "Fixes #1 and
doesn't fix #4" fixes #1 alone. A negation anywhere else, as in "Fixes #1, which was not a
regression", leaves the fix standing. A release PR (one that changes only `.claude-plugin/plugin.json`)
fixes nothing. The section reads `outcomes`' `rework` column, so a story merged 7 days ago or less
counts as rework only once its fix has merged. `outcomes` lists the merged PRs with `gh`, the last 1000 per repo. A line on stderr
says when a list comes back that long, leaving rework unknown for the PRs merged before its oldest.
When `gh` fails or a list is that long, unknown rework counts as none, and a line under the table says
so, as under `reviewers`. A `mergedAt` that does not parse leaves its PR
out, counted in one line on stderr. A cell with fewer than 5 stories prints its count and `-` in the other columns,
as too few to judge. After a blank line, a `subagents` block gives a row per model and effort of
the builds whose subagents cost more than zero (`outcomes` writes `0.00` for a build that ran
none): what their subagents cost, the build cost (theirs plus the
builder's own), and the subagents' share of it.

The `predictions` section scores the planner's `easy` labels and `estimate_lines` against what the
builds took. It reads `.swarm/dataset.jsonl`, which `swarm.sh dataset` writes, and counts the stories
merged in the window. With `--epic`, it counts only the stories whose text has that `epic:`. It prints TSV `planner_model stories easy_precision easy_recall estimated
est_err_median est_err_mean`, one row per planner model (`-` when `dataset` found none) and a last
`all` row:

- `easy_precision`, of the stories labelled `easy: true`, the share that `was_easy`;
- `easy_recall`, of the stories that `was_easy`, the share labelled `easy: true`;
- `estimated`, the stories with both an `estimate_lines` and a diff size;
- `est_err_median` and `est_err_mean`, the median and mean number of lines those stories' estimates were off by.

Both shares print as `hits/total percent`, or `-` with none to count. A story whose `easy` or
`was_easy` is unknown counts in neither. A window with no stories prints a line saying so in place of
the table. A last line counts the file's lines the section could not score: lines that are not JSON,
or that have no `inputs` and `results`. With no `.swarm/dataset.jsonl`, the section prints a line
saying to run `swarm.sh dataset`.

The `throughput` section prints one TSV
row per epic and a last `all` row for the project, over the `outcomes` rows dated in the window and
the `events.tsv` lines whose local day is in it. With `--epic` it prints that epic's row alone. `builders_mean` and `builders_max` say how many builds ran at once,
weighted by time, from the first build's start to the last one's end. A build runs from its
`outcomes` `started` until its first `close` after that which no earlier build of the story took,
and before the story's next build with a known start, or else its session log's last entry, and never past local midnight at the end of
the `--until` day. A build with no `started` starts at 00:00 local time on its agents.tsv day, or
when the story's last build with a known end ended, if that is later. A build whose start can't be read is left
out.
`stories` counts the slugs built, `longest_chain` is the longest `depends_on` chain among them (each
story is read from the board or from git history, so merged stories count), and
`stories_per_chain` divides the two. `review_wait_min` is the mean time in minutes from a PR's
`createdAt` (from `gh`) to the first `review-agent` event for its slug. A PR with no such event goes
into `proxy_review_wait_min` instead, timed to its first `tell:findings` or `review` event. Those events
come when a review ends, so the two columns are never averaged together. `stacked`
counts the `stacked` events for the epic's slugs, or all of them on the `all` row. The project
row comes last, so an epic named `all` still gets its own row above it.

The `time_in_state` section prints TSV `epic prs hours largest_first ready_wait_median ready_wait_p90`, one row per epic and a last
`all` row. With `--epic` it prints that epic's row alone. The five phases are summed over the
`outcomes` rows dated in the window that have the phase columns (their PR merged). Each PR counts
once, by its build that started first, since a retried PR repeats its phases on every build, and is
in the window only when that build's date is. `held` is over the same PRs: the `held_min` of each of
their stories, once, from its earliest build. `hours` is all six together, and `largest_first` gives each as
`<state>:<hours>h/<share>%`, the largest first, where the share is of `hours`. So
`held:3h/64% review_wait:0.6h/12% fixing:0.4h/9% ci:0.2h/5% merge_wait:0.2h/5% building:0.2h/4%`
says the epic's stories spent most of their time waiting to start. The last two columns,
`ready_wait_median` and `ready_wait_p90`, are the median and 90th percentile (nearest rank) of
`ready_wait_min` in minutes, over the stories whose first build is dated in the window, merged or
not. They are empty when there is none, and an epic with only such builds still gets a row.

The `idle_slots` section asks whether the swarm sat idle while work was ready. It prints TSV `epic
idle_min no_conductor_min most_ready`, one row per epic and a last `all` row, or the `--epic` row
alone. When no story (or none of that epic) waited in the window, the line `no story was ready in
the window` (or `no story of epic <slug> ...`) replaces a row of zeros; a story covered by its own
running build did not wait. `idle_min` is the minutes in the window when at least one of the epic's
stories was ready with no build while its conductor ran. A story goes ready at an `unblock`,
`reconcile ... ok (reopened)`, `reset` or `reset:held` event, or at a close that sent it back to
ready. That is any close except the first one after a `review` or `kept` event for the build, which
leaves the story in review (a later close, the drop, sends it back). Every wait counts: the first
runs from the first build's start less its `ready_wait_min` (or from a later event that readied the
story, such as a reset), and each later one from the story going ready again to its next build. A
story is not waiting while its own build runs. A story on the board now that `next` would build
(`status: ready` with `.swarm/board-state` laid over its file, a kind an agent builds, no epic or an
`active` one, and not held) with no build since it went ready waits until the end of the window. A
build since is one that ran past that time and started at it or later; a build the readying close
ended, however short, is not. For that wait, the board's last commit to its status line on the
default branch, dated by the merge, also readies it. A ready story that clashes with a running build
(their `touches` in the same repo, as the clash rule reads them, with the project's `repos_dir`,
unless one depends on the other) could not start, so those minutes are not idle. A build from before
`--since` still clashes: its story is read from the board or, once merged, from git. When a git call
fails, the section warns once on stderr, as what it reads is then left out. The same minutes with no
conductor of the epic running go under `no_conductor_min`. `most_ready` is the most of its stories
ready with no build at once, clashing or not. The `all` row counts a minute once however many epics
were idle in it, and it includes the stories with no epic, under the backlog conductor. Builds keep
`agents.tsv`'s order. Each runs from its start to its slug's next ok close or `reconcile ... ok
(finished...)` (reconcile closes a merged story's builder itself), else to its next build, else to
the end of the window. A build with no session log yet starts at 00:00 on its `agents.tsv` day, and
no earlier than the build before it ended. Such a build counts as built since its story went ready,
unless a close readied the story. A conductor runs as `held_min` reads it: from an ok `conduct`
event until the next one, a close of its agent or its report. A backlog run ends on a close of
`conduct-backlog` or of the project's own backlog conductor name.

The `features` section asks whether each feature is worth keeping. It reads the project's own
`docs/features.tsv`, or the file `SWARM_FEATURES` names. With neither, it prints one line saying
there is no feature list, so a project never sees swarm-dev's own features judged against its logs.
The file lists every feature with when it landed (a date, a `#PR` or an epic), the metric it
should move (as a `flow` section or `outcomes` reports it), that metric's baseline
from before it landed (a value naming the command and window it came from, or `unavailable: <why>`),
and its uses. A use is an `ok` `event:<command>` line in events.tsv, by its local day (a `tell` also matches
`tell:findings`), a `role:<role>` or `agent:<name>` line in agents.tsv, or a `reviewer:<who>` row in
findings.tsv. A read-only command leaves no events line, so its uses say `unlogged: <why>`. The
report prints each feature's uses in the window, its metric and its
baseline, and marks `delete?` a feature with no metric, or one whose logged uses have none in the
last 30 days. A feature still settling in is never marked `delete?` for having no uses: one that
landed in the last 30 days, or whose `landed` names an epic still on the board. Both are read in the
repo that holds the features file, since its PRs and epics are there and not in the project being
reported on. A `#PR` landed on the day of the oldest commit whose subject ends `(#N)`. An epic is on
the board while `<board_dir>/epics/<name>.md` exists there, and landed on the day git log shows that
file deleted. The installed plugin carries its board but is not a git checkout, so
`docs/features.tsv` itself gives dates. An epic with neither is judged by its uses, and so is a
`landed` that can't be read, with a warning on stderr. An unlogged feature is judged on its metric alone.
Without `--since`, the window is the 30 days up to `--until` (or up to today). The section ignores
`--epic`.

The `reviewers` section shows what review yields, so the
reviewers can be tuned. The first block is TSV `reviewer kind raised fixed declined decline_rate rework`,
counted from `findings.tsv` rows dated in the window. Each reviewer gets an `all` row and then
a row per kind, most declined first. Rows from before the reviewer column count as `unknown`. Then
come an `all <kind>` row per kind across reviewers and a last `all all` row. The decline rate is
declined over raised as a whole percent. `rework` counts the PRs that line raised a finding on in the window and that
`outcomes` shows as reworked. When `gh` failed for `outcomes`, a last line says rework is unknown. After a blank line, the second block is TSV `prs rounds
rounds_per_pr max_rounds`: the `tells_findings` of every `outcomes` row that has a PR and is dated in
the window, summed per PR, so a PR built twice counts the rounds of both builds and a retry
with its own PR keeps its own. A tell names no reviewer, so rounds are not split by one. With no
`agents.tsv` the second block is all zero. So the window keeps the findings dated in it and the
rounds of builds started in it. `--epic` keeps only the PRs whose builds carry that `epic`
in `outcomes`, in both blocks, and lists in a third block every PR that either block counted, so you
can check what was covered.

When a large epic was split, a block between the two is TSV `split critic_fixed critic_declined
escaped_split_gaps`, one row per split's board PR: the split critic's fixed and declined findings
beside the `split-gap`s logged `--reviewer escaped` against that PR, the gaps it missed. Every
split `board-pr open` recorded in `.swarm/<epic>/split-pr` has a row, a clean one (the critic found
nothing) as `0 0 0`, dated by the day it opened; a split with no record is dated by its first row.
A split is in the window when that day is, and every escaped split-gap counts against it whatever
its own day. `--epic` keeps the splits of that epic or of its `parent:` (read from the board, or
from its last version in the board's git history once the child is gone). The record names a
split's epic; for one with no record `gh` reads the PR's branch (`board/scope-<epic>`), and when gh
fails a note says how many splits it could not place. The split critic's tokens have their own `split-critic` row in `cost`.

Once a row in the window has a review round (`--round` on its findings), two more blocks follow the
rounds. The first is TSV `round reviewer fixed declined nit out-of-scope wrong share_fixed`: per
round, each reviewer and then `all`, the findings fixed, declined in all and by reason, and fixed
over raised as a whole percent. Round `0` is a plan or board PR, and `unknown` holds the rows logged
without a round. The second is TSV `story pr stopped_round why`, one row per story PR with a round
of 1 or more: the round its review stopped in, and why. A final pass that finds nothing logs no
row, so the stop is the review after the PR's last round of findings sent to its builder (the
`tells_findings` of all its builds, whatever their date, plus one), or its last logged round when
that is later. A PR is listed when the window has a row of it with a round, and where it stopped is
read from all its rows, whatever their date. For a merged PR, `pass` means the stop round fixed nothing and `merged-after-fixes`
that it fixed something. A PR that has not merged shows `unmerged`, since its review may still be
going. `--epic` narrows both blocks as it does the others.

The `review_loops` section shows what each review round cost and what it bought, so the stop and
escalation rules can be tuned. It reads `events.tsv`, `findings.tsv` and `agents.tsv`, and calls no
`gh`. Each build of a story (an `ok` `story` line, an `ok` `agent` line for a builder a conductor
started, or an `escalate` build's `ok (attempt N)` with the `story` line after it) is its own loop,
with its own rows; a `merge` line ends its loop, and the lines after it count for none until the next
build starts. A loop is listed when a `review-agent`,
`tell:findings` or `escalate` line of it falls in the window, by local day, and `--epic` keeps that
epic's stories (from `outcomes`). A `review` line counts once for each PR it names, as that PR's
story's (found through `outcomes`, so an epic's review reaches its stories), else as its target's. A
loop's PR is the URL on its `ok` `review` line, else its build's `outcomes` row's (the row of its
builder's latest `agents.tsv` line, as `outcomes` has one row per 7-field line), else `-`. Rounds
count per PR, as findings' `--round` numbers them (the n-th review of a PR is its round n): a build
on a PR starts after the rounds of the builds on it before. Each finding with a `--round` goes to one
loop, the one whose rounds hold its round (the last on its PR takes any later round), so two builds
on one PR never count a finding twice. A finding with no `--round`, or on a PR no loop has, counts
nowhere. Its rounds go in log order: an `ok` `review-agent` opens one, and a review agent started again
before the round closed moves its start; an `ok` `tell:findings`, a `findings-*` step-up (which takes
the tell's place), or the `ok` `review` or `merge` after the last tell closes it. A round no review
agent opened has no minutes.

The first block is TSV `story pr round model minutes fixed declined step_up`, a row per round: the
builder's model (each build start and each step-up takes the next of the builder's `agents.tsv`
lines in a builder role, and a step-up's model is its `to`), the minutes from the review agent's
start to the round's close, the findings fixed and declined given to the loop with that `--round`,
and each step-up in the round as `<trigger>: <from> -> <to> ok`, or `failed` for one that failed
partway, after its builder was closed: a `step-up` or `step-up --resume` whose error says the builder
is closed, but the next did not start (trigger `?`), or a `tell` or `close` whose step-up failed
partway (a tell's has trigger `findings` and closes the round, and a findings step-up resumed after
it goes on that round). A step-up refused before it changed anything (`nothing was closed`) is not
one. A step-up before the first round shows on round 1, ending `before review`; a loop with no round
shows its step-ups on a row whose round is `-`. A PR whose findings name a later round than its
events gets rows up to it. The second block is TSV `story pr rounds end`, for each loop with a round, `rounds` its PR's last
round in that loop:
`held-for-lead` after an `escalated` line; once the PR merged (a `merge` line, or merged in
`outcomes`), `pass` when its last round fixed nothing and `merged-after-fixes` when it fixed
something; else `open`, a PR handed over by `review` and not merged among them. The last is one TSV
row over the loops with a round: the PRs (each once, loops with PR `-` left out), the median and p90
(nearest rank) of their rounds, the minutes spent in round 3 and later (a round with unknown minutes
adds none), the fixes, the share of them found in round 1, round 2, round 3
and later, and on the top rung (`escalate_ladder`'s last model; `-` with no ladder), the builds that
stepped up with their fixes per round up to and after the first step-up, and the failed step-ups.
With no story in the window it prints one line saying so.

The `test_runs` section shows how long local test runs take under load, so a test queue or a `JOBS`
change can be decided from numbers. `scripts/test.sh` appends a line to the main checkout's
`.swarm/test-runs.tsv` as each run starts and as it ends. It finds the file through `git rev-parse
--path-format=absolute --git-common-dir`, so every worktree's runs land in one file, and never
through `SWARM_PROJECT`, which tests run without. A line holds the start and end times (UTC), the
seconds taken, `JOBS`, the filter, the branch, the 1-minute load average and the CPUs, how many other
runs were going, the exit status, and the run's PID. The filter is `all` when the files run are every
`tests/*_test.sh`, else `TESTS`, else how many files (`1 files`), with ` shard i/N` after it for a
`SHARD` run, which is no full run. Each line reads the load, CPUs and other runs at its own moment,
and the start line leaves end, seconds and status empty, so a run that was killed still leaves its
start. A run counts as going while its mark, a file named by its PID in `.swarm/test-runs.d/`, is
there: test.sh writes it at the start and removes it at the end, and a mark whose PID has gone is
removed when the next run counts. A write that fails is skipped and never changes the run's exit
status. A `TEST_RUNS_LOG` that is set names the file instead (empty logs nothing); test.sh sets it
empty for its jobs, so a run a test starts itself logs nothing and is never counted as going.
The section reads the full runs (`all`) whose start falls in the window, by local day, less those
interrupted (a status of 128 or more) and torn lines (one cut short). Each end line pairs with its start line (the same start time and PID), and a run's at_once
is the larger of the two lines' other runs, plus the run itself. It prints TSV `at_once runs
median_s p90_s median_load`: the runs by at_once (1, 2, 3-4 and 5+), each with its median and p90
(nearest rank) seconds and the median load at the start (`-` with no run). After a blank line, TSV
`start seconds branch at_once status` lists the 5 slowest. These two blocks are the baseline for
full runs. After another blank line, TSV `builder_runs median_s p90_s` counts the runs on `story/*`
branches whose start falls in the window, of any filter. A `TESTS` run, an `N files` run and a full
run count; a shard run, an interrupted run and a torn line (one cut short) do not. It gives the count
and the median and p90 (nearest rank) seconds, `-` with none. With no log, as in a project with no
`scripts/test.sh`, it prints nothing. With no full run in the window, a line that says so takes the
place of the first two blocks. `--epic` does not narrow it.

## The outer loop

Each finding that review fixed is logged with
`swarm.sh log-finding --reviewer <who> <kind> <PR> "<one line>"`, where the kind names the class of mistake
(`vacuous-test`, `denylist`) and `<who>` is the reviewer that raised it: `codex`, `fallback` (the agent codex-review starts in codex's place on a usage limit), `code-review`, `ci` (a
PR review bot, a check-run note or a code-scanning alert), `conductor` or `lead`, or `skeptic` and `critic` for a plan review's finding on a board PR, and `split-critic` for the check on a large epic's split (commands/plan-epic.md step 0). A defect that a later fix finds in merged work is logged against the original PR with `log-finding --reviewer escaped <kind> <original PR>`. Its outcome is `escaped`: it counts toward the `recurring` block, but `outcomes` and flow's `reviewers` leave it out, since review missed it. Each finding declined is logged with `log-finding --declined <reason> --reviewer <who>`, where the
reason is `out-of-scope` (outside the story's touches and **Done when**), `nit` or `wrong`, and the row keeps it as a seventh field; `outcomes` counts fixed and declined apart, and its
`recurring` block counts the fixed and escaped ones, never the declined. `--round <n>` records the
review round a finding came from: the n-th review of a story PR is round n, the passing one included,
and a plan or board PR is round 0. The conductor passes it on each finding it logs, and flow's `reviewers` counts each round's yield from it. When a conductor finishes,
`/swarm-dev:swarm` files one story with `checks: <kind>` for each recurring kind that has no check
yet, in a board PR named `check-<kind>` (written in place when the board is outside the repo, and
noted in `.swarm/checks-filed.tsv` so the kind is filed once). The
story adds a test, lint rule, hook or review-prompt line that catches the kind, since a rule pasted
into a prompt does not stop the mistake by itself. While that PR is open, once it has merged, or for
90 days after you close it unmerged, the kind gets no new story. Once the
check merges, `outcomes` shows whether the kind came back less often, and `/swarm-dev:swarm` tells
you when its fixes after the merge reach 3 PRs. The log is `.swarm/findings.tsv`, local to
the machine: date, kind, PR, the line, its outcome (`fixed`, `declined` or `escaped`; rows written before the
outcome column count as fixed) and the reviewer (`unknown` when a row was logged without `--reviewer`
or before that column existed), then a declined row's reason and, with `--round`, the round (after an
empty reason on a fixed row). A row with no round is round unknown. Columns added later go on the end,
so readers ignore any they do not know.

**Green means more than green checks.** A check can pass and still carry a failure note (a
code scanner often does), so the lead also triages `swarm.sh findings <repo> <pr>`: the notes on
every check run of the PR's head, and its open code-scanning alerts (the first 100 of each). Each is fixed, or rebutted in
the PR with a reason; none is silenced or dismissed. findings also reads the PR's diff and body. A
test the diff adds (Go `func TestX`, Python `def test_x`, a `check` line in `tests/*_test.sh`, a JS
`it(` or `test(`) needs a line in the body with FAIL and its name, which the builder pastes from the
mutation run. findings prints each test without one as `rules-unchecked`, with the command that
logs it, `log-finding --reviewer ci`.

## Merging

With `merge = human` (the default) no agent merges: each agent starts unable to run
`gh pr merge`, its brief forbids every other route, and the plugin's merge guard (below) refuses the common ones. When a PR is green and reviewed, the lead
runs `swarm.sh review <slug> <PR URL>...`, which sets the item `status: review` with its PRs on a
`prs:` line, and `next` lists it as awaiting your merge. When the stories left in an epic are all
in review and its **Done when** will hold once they merge, the conductor puts the epic in review
too, with every PR still waiting. A `kind: lead` story whose `after:` names its own epic does not count in it
(alone or in a list; an `after:` that does not name its own epic is ignored), so an epic with only
such stories is still planned.
An active epic that had code stories planned (on the board, in its git history, or a board not in
git, which has none to read), none of them open, counts as done in `next`,
`status` and `dash` while its `after:` stories wait, so an epic or story that `depends_on` it goes
ahead. On a board in the story's repo, its last code story's PR deletes the epic file without them.
The `after:` story stays on the board and is listed with the lead's stories. You merge on GitHub; the next `/swarm-dev:swarm` runs `swarm.sh reconcile`,
which finishes each item whose PRs have all merged and sends back to `ready` any item with a PR
closed unmerged; that item keeps its `attempts:`, and reconcile never counts one. While the story
file still names its repo, it also clears each story's build away: its worktree, and `story/<slug>`
here and on origin. A merged story's build always goes; if its builder is still open, reconcile
closes it first, which counts nothing while the story is in review. After a PR closed unmerged, the
build goes only when no builder is open, and the story can then be built again. An open builder may
be fixing that PR, so reconcile keeps its build and prints `build kept: <slug>`. It does the same when
herdr cannot list its agents, since a builder may then be open unseen. After a merge it clears the
build even then, and prints `build cleared: <slug>`: close that builder's pane yourself with
`swarm.sh close <slug>`. Outside herdr it treats every builder as closed and never calls herdr.
Then it pulls the board's repo, fast-forward only. swarm.sh keeps its own keys out of tracked files
(§ Building, Board state), so a main checkout with no edits pulls as it is. With nothing to pull (the
main checkout already has every upstream commit), reconcile goes on and leaves every edit as it is.
reconcile touches nothing, and stops naming why, when the main checkout cannot fast-forward (it has
local commits), or when a tracked file the incoming commits change is changed there too, staged or
not. A changed file the pull leaves alone, such as Obsidian's own settings, stays as it is. A story
or epic the pull changes whose only uncommitted change is to swarm.sh's keys, as an older swarm.sh
wrote them, does not stop it: reconcile moves the values, as the item reads them, into its state and
checks the file out, so the item reads as it did. It stops instead, naming the file, when the incoming
commits change that file's `depends_on` or the same keys, since the old values would read over the new
ones (a status flipped to `ready` over a new dependency): check the file out, and once the pull is in,
set its keys again through swarm.sh. The same value on both sides goes through. A `status` and `prs`
the incoming commits change are the exception: the old ones give way and are dropped, so a story
whose merged PR set `status: done` reads as done. reconcile names each uncommitted value it dropped
that way, with the one that replaced it, so you can set it again if you meant it; an older
swarm.sh's `review`, `building` or held status that an incoming `status: done` finishes is not named.
An untracked board file whose bytes match the incoming file's is removed, and the pull brings it back. A pull git refuses (an untracked file it
would overwrite) also stops reconcile, and reconcile puts back each of those changes first, so a
failed pull changes nothing. On a stop for changed files, it names each of them and logs an
`incident` line in events.tsv with the outcome `pull-failed: <files>`, once while the same stop
lasts. For a board
file it says to land the edit through `swarm.sh board-pr` or check the file out to drop it; for any
other file, to commit or move the change. Then run `swarm.sh reconcile` again. On a board in the
repo, reconcile never deletes a tracked file in the main checkout. An item whose PR merged but left
its file on the board is marked `done` in its state after a pull, or at once when the checkout's
branch has no upstream (there is nothing to pull), and stays on the board until
`swarm.sh finish <slug>` takes it off through a board PR. When reconcile holds the pull because it
cannot read a PR in review, the item stays in review until a later reconcile pulls. On a board outside the repo it deletes the file of the item that merged.
Reconciles in one project run one at a time (merges through a merge queue run side by side): one
waits up to 300 seconds (`SWARM_RECONCILE_WAIT`) for `.swarm/reconcile.lock`, then stops naming it. `swarm.sh unblock` then readies a
blocked story once every slug in its `depends_on` is finished. It leaves an old `blocked_by` line as it is, since nothing reads it. With `merge = agent` the conductor merges instead, only through `swarm.sh merge`, except for a story with `costs: money`: `swarm.sh merge` holds a PR whose story, or a story it stacks on, has `costs: money` or any other value but `none` for you, on every route (`held: <slug> costs money`). A `costs:` of `none` or empty merges, and an unreadable board story holds every PR (it fails closed). The conductor reviews a held PR, closes its builder and leaves it for your merge. Only the conductor merges. Every agent, the conductor included, still starts unable to run `gh pr merge`. The head a review passed is the `head:` line of the
story's findings file; once the review passes, the conductor reads the PR's head again, and if it is
not that SHA, it reviews the new head. Then it runs `swarm.sh review <slug>
<PR URL>`, then `swarm.sh merge --head <that SHA> <PR URL>`, which merges by the literal PR number
with `--match-head-commit` (with `--auto` only to enqueue it on a base with a merge queue), waits for CI on the base, and runs `swarm.sh reconcile`.
That pulls the board the way it does for you, and finishes
the story, closing its builder. The conductor never closes the builder before that, because closing
a story that is still `ready` counts a failed build. Its first `swarm.sh merge` shows whether the
base has a merge queue. Where it prints `merge queue: <base> has one`, the conductor starts `swarm.sh
merge` for every PR whose latest head passed review as soon as it passes, without waiting for the
ones before it to merge, so the queue tests them together and merges them in batches. Otherwise it
runs one `swarm.sh merge` at a time, and starts the next only once the last has exited. After each merge, and after each wait once it has
read its inbox, it runs `swarm.sh unblock --startable <epic>` (`--backlog` for the backlog conductor) and,
in the same run, starts each story printed as `startable:` that clashes with no running one (§
Building, Pick the wave). `--startable` runs unblock, then prints `startable: <slug>` for every `ready` story in that
scope with no worktree yet, whether or not this unblock readied it. A story that a board PR adds
already `ready` starts the same way. It reads the board as reconcile last left it and never pulls:
pulling is reconcile's job, which `swarm.sh merge` runs. A line ends `(stacked on <parents>)` while
the story's `depends_on` has open stories, and `(its PR <url> was closed unmerged)` when reconcile
last sent it back to ready; the conductor leaves that one for the lead. A build cleared on error or given up on stops that: it starts nothing more in
the wave. Once the epic's file is gone (its last story's PR deletes it), `--startable` still runs unblock
but lists nothing. The
conductor skips a story it closed in this wave (it may start it again in a later one), one its give-up rule says not to start again, and one
a `not held:` line left `ready` for the lead. If the last inbox pass before its report reads a note,
it runs `--startable` once more, and if that starts a builder, it goes back to waiting instead of
reporting. It reports once no story of the epic that it may start is ready and none is running. If
CI on the base times out, it merges nothing more and stops, and says so in its report. If it goes
red, `swarm.sh merge` prints `fix-main:` and writes the fix-main story (below): the conductor starts
its builder at once, ahead of every other story, and merges nothing else until that fix lands. It stops only when what is left needs the lead: a story only
the lead can finish, or a merge that `swarm.sh merge` refused or could not confirm. The lead merges
with `swarm.sh merge`: a one-off story with `merge = agent`. Under `merge = human` it merges a story
PR or board PR only when the agreed HLD over it lists `merge` in its `grants:` (the HLD
`swarm.sh grants <PR URL>` prints). It reads that grant once the PR's head is green. With the grant,
the holds of `merge = agent` apply too, so a `costs: money` story's PR, and a board PR that changes a
`costs:` line, still wait for you. Without it, `merge` refuses with
`<PR URL> waits on the user's merge (merge = human, and no HLD grants merge for it)`. When a board
story, the PR's files, or its head or base cannot be read, so the HLD over it is unknown, it refuses with
`cannot tell which HLD <PR URL> is under, so it waits on the user's merge`. `merge` reads the grant,
and the PR's files, at the head and base branch it pinned. When the PR's head has moved off it,
`merge` refuses with `the head of <PR URL> is <sha>, not <pinned sha>, so no grant covers it: review
the new head`, and when the PR has been retargeted, with `the base of <PR URL> is <branch>, not
<pinned branch>, so no grant covers it: review it against <branch>`. GitHub lists 300 files at most
at a given head, so a PR that changes more gets `cannot tell which HLD`. When the HLD's `grants:`
holds a value swarm.sh does not know, or is not a one-line `[..]` list, it prints the line naming the
HLD's file and line, then refuses with
`the grants: of <HLD file> cannot be read, so <PR URL> waits on the user's merge`. Under `merge = human`,
`--release` merges only when the release is covered: at least one story file was deleted by the
base's own commits since origin's tag `v<base version>` (a merge commit's deletions count against
its first parent), and every such story, read as it was just before the commit that deleted it,
falls under an agreed HLD that lists `release`. It reads the board from the base on origin, since
your checkout may not have pulled. The story's epics are read as they were then, except that the
base's copy wins where it still has one. Its HLD comes from the base alone, so deleting an HLD, or
taking a grant off one, stops it counting once that change is on the base. A
story the base's board still holds, marked `done` in your board state because its PR left the file
in place, must fall under such
an HLD too when a PR from its `story/<slug>` branch merged since the tag, and then counts as a story
merged, or when gh cannot list those PRs, and then does not. Otherwise it refuses with `<PR URL> waits on
the user's merge (merge = human, and story <slug>, merged since v<version>, is under no agreed HLD
that grants release)`, naming the
first story it found uncovered. A board outside the project's repo never covers a release. A
covered release still goes through the docs check below.

`swarm.sh merge [--board|--release] [--head <sha>] <PR URL>` merges one PR. It refuses, merging nothing,
unless the PR is open, its head is `<sha>` when `--head` names one, and a story or epic in `review`
lists the URL on its `prs:` line. With `--board`, for a board-only PR, the PR must be in the
board's own repo (its origin) and every path it changes, a renamed file's old path too, must be
under the board instead. Under either merge mode, `--board` also refuses a PR that sets an epic
`active` with no ticket, as `board-pr open` does (§ The lead). Once the head is green, it reads each
epic and HLD through gh at the PR's base branch and head SHA. Any read error refuses, as does a 404 at
the head on a file the PR does not remove or rename away. With
`--release`, for a release PR, the PR must be in the project's own
repo and go into its base, and it may change only `"version"` in `.claude-plugin/plugin.json`, since
hooks, MCP servers and command paths there run code. The new version must be MAJOR.MINOR.PATCH and
greater than the base's. When `bin/`, `commands/` or `hooks/` changed between the tag
`v<base version>` and the base but README.md, AGENTS.md and `docs/` did not, it refuses and names
the changed paths, unless the PR body has a `Docs: none — <reason>` line. That line may be a `- `
or `* ` list item and may use `-` or `--` for the dash. The reason must be at least two characters,
and a placeholder such as `<reason>` does not count, nor does a line inside a ```` ``` ```` fence or
a `>` quote. A change to `commands/*.md` is the text a user reads, so it covers itself when nothing
else in the code changed; next to a `bin/` or `hooks/` change it does not. The board's own paths
(`stories/`, `epics/`, `hld/`, `Board.base`, `.obsidian/`) are not docs, even when the board is
`docs/`; the rest of `docs/` is. It compares against origin's tag by its SHA and never fetches
over your local tag. It refuses when origin has no
such tag or the tag is not on the base. No story or epic need list it. These checks all read one
commit of the base: `--release` fetches the base from origin first and remembers what it got. Right
before `gh pr merge` it fetches the base again. If the base moved, it prints `origin/<base> moved
from <old> to <new> since the release check, so it runs again`, runs every `--release` check again
on the new base, and refuses if one fails. A story that landed in between under no HLD granting
`release` is refused like any other.
The head must be green: at least one check run, every run
completed as success, skipped or neutral, and every commit status a success. It reads every page,
and any gh error or answer it cannot read is a refusal. It merges with the repo's method (squash
when allowed, else a merge commit, else rebase) and `--match-head-commit`, so a head that moved
after the check stops the merge. It never passes `--auto`, except to join a merge queue (below). It passes `--admin` only with `merge_admin = on`, and only after `ci_gate admin` passes (§ Settings).

**Merge queue.** With `merge_admin` off, `merge` asks GitHub whether the base has a merge queue
(GraphQL `repository.mergeQueue(branch:)`, which covers a ruleset's `merge_queue` rule and classic
branch protection alike) before it merges. When it has one, `merge` enqueues the head with
`gh pr merge --auto --match-head-commit <head>` (the queue picks the method) instead of merging.
The queue tests the PR on top of the base and the PRs queued ahead of it, so two PRs that are each
green alone but red together never land. `merge` reads the PR back even when gh fails, since an
error can follow an enqueue GitHub made, and a PR already in the queue is waited on as if it had
just joined it. It prints `merge queue: <base> has one` first, whatever happens next. Then it reads
the PR every 20 seconds until it merges or leaves the queue, and checks its head on every read. The
30 minutes for CI start when the PR's own merge group starts, and again for each group the queue
rebuilds; waiting its turn behind other PRs, or for auto-merge to enqueue it, has a bound of its own,
six times that (3 hours), which starts again when the queue takes its group apart. A head other than the one it checked stops the wait:
`merge` turns auto-merge off and takes the PR out of the queue (GraphQL
`disablePullRequestAutoMerge` and `dequeuePullRequest`), so a push made before the PR reached the
queue never merges unreviewed. If the PR has already merged at another head, `merge` logs
`merge merged at head <sha>, not <sha>, ...`, runs reconcile (main has changed) and exits non-zero,
so the merged code gets a review. A merged PR logs `merge ok`, and a
`main-ci` wait follows before reconcile, as for a direct merge: the queue ran the PR's checks on its group, but the
workflows that run only on a push to the base (a release, a deploy) run where the base was pushed.
The queue pushes a batch of PRs at its last commit, so `merge` waits on the base's head once it holds
the PR's merge commit, not on that commit itself. A PR that reads merged
before GitHub shows its merge commit is read again, up to three times. A PR that leaves the queue
unmerged is a dequeue when GitHub logged its removal after this enqueue (one dropped within seconds
for a conflict counts, an earlier run's does not), even while its auto-merge still reads on, which
`merge` then turns off; or when three reads in a row, after one showed it
queued or waiting for auto-merge, find it out of the queue and not merged. `merge` exits non-zero with one
`merge dequeued (<GitHub's reason>): <checks>` line naming the checks that were red or unfinished on
the merge group's commit. That commit is the one seen while the PR was queued, or, for a PR that
joined and left between two reads, the one its `merge_group` run names; the reason is GitHub's only
for a removal after this enqueue. The conductor handles a dequeue like a red check: it sends the
failing checks to the builder, which merges the base in and pushes, then reviews and merges the new
head. A wait that runs out or errors, a PR that never reads as queued, and a TERM, HUP or INT
while `merge` enqueues or waits each turn auto-merge off and take the PR out of the queue. Each is logged as
unconfirmed (`stopped by SIGTERM` for a signal), naming anything it could not undo for you to do by
hand; running `merge` again enqueues it again. A PR that never reads as queued after gh failed on
the enqueue is a refusal instead. If the queue cannot be read (three tries), `merge` refuses and merges nothing: on a
base with a queue, a direct merge would enqueue the PR with nothing watching its head. `--release`
never joins the queue, where a PR queued behind it could share its push and so its tag, and a base
that requires a queue takes no direct merge but `--admin`'s, which `merge_admin = off` rules out. So
`merge --release` refuses there, naming the queue, and the release is yours to merge once the queue
is empty. With no
queue the path is the one above. ci.yml and zizmor.yml run on
`merge_group`, and ci.yml's gate reads the base's copy of board-only.sh from the merge group's base,
so the required checks report on each group. infrafactory keeps no queue: its ruleset needs an approving review, and `merge_admin = on`
merges with `--admin`, which would skip a queue. `ci_gate admin` refuses a base with a
`merge_queue` rule for that reason.

It reads the PR back after `gh pr merge`, whether gh succeeded or not, since an error can follow a
merge GitHub made. A PR that does not read as merged is read again a few times, then logged as
unconfirmed, for you to check by hand: it may well have merged. Only a failed `gh pr merge` on a PR
that still reads open or closed is a refusal. Then it waits up to 30 minutes for CI on the merge
commit, so run it in the background: each workflow whose `on: push` filters cover the base and the
files the PR changes must have a run on that commit, and every run and check there must pass. The
commit needs no check run of its own when no workflow is expected on it, but then it waits a minute
before calling main green, for checks other apps post just after the push. A failed read is a
missed poll, and three in a row end the wait as an error. When the base requires status checks (its
rulesets and branch protection, read once per merge, each check bound to the app the rule names),
only those can make main red. When any part of the rules cannot be read, merge prints `warning:
could not read <base>'s required checks (<why>), so every check counts`, and every check does. Any
other red check or workflow run waits until each required check has a run on the merge commit (a
workflow that never started holds main until the wait runs out, and the timeout names the required
checks with no run). Once every workflow expected on the push has finished, a required check still
with no run (a `pull_request`-only one, say) will never get one, so every check counts from then
on. Otherwise, once each required check has a run, a red that is not required prints `warning: <check> is red on <base>, which does not require it` and
leaves main green. Once every required check has finished green, nothing else is waited on. A
red whose every check is a GitHub Actions job gets one rerun per run: once those runs have
finished, merge reruns their failed jobs (`gh run rerun --failed`) and waits again, for the full
time. A red whose run, or rerun, is still going when the wait runs out is red. A transient gh error on the
rerun (a 5xx, a rate limit, a dropped connection) is a missed poll, and three in a row end the wait
as an error. If a rerun goes green, merge
prints `flaky: <jobs> (<the FAIL lines of the attempt that failed>), green on rerun` and logs a
`flake` line. If it goes red again, merge writes the fix-main story. A red that is not an Actions
job writes the story at once, and so does a rerun GitHub refuses. A `note:` line first among the
story's CI output, and among merge's, says that the rerun failed too, or why GitHub refused it, and
names any rerun still under way. `swarm.sh reconcile` clears a red main by the same rule: once each required check
has a run, only those must pass. Without
`--board` or `--release` it then runs `swarm.sh reconcile`, also after a red main, since the PR has merged.
With `--board`, on a green main and when the main checkout has an upstream, it runs `swarm.sh
reconcile` too, which pulls the board. A story counts as newly ready when it was not buildable before the merge, is now,
has not started building, and has a file the board PR itself changes that wasn't buildable on the
board the PR merged onto (the first parent of the PR's own merge commit, even when a merge queue
pushed it with others; for a rebase merge, the commit below the PR's first) and is at that merge
commit, or an epic file that the PR changes for an epic that wasn't `active` there and is at the
merge commit. A story reconcile sent back to ready doesn't count, nor
does a `fix-main` story, or one readied by an earlier board PR that merged but was not pulled here yet. For each epic with newly ready
stories, it sends the epic's running conductor one note naming them (`swarm.sh tell conduct-<epic>
note`; stories with no epic go to the backlog conductor) and asks it to start them now, within its
builder limits. A conductor that has written its report has finished and counts as not running.
When no conductor runs, it prints a `ready now:` line, then starts one (§ The backlog conductor says
when). It prints a warning, and the merge's exit status stays the same, when reconcile fails (logged
as a `reconcile` line, as merge logs one), when reconcile did not pull the merge commit, when herdr
cannot list its agents, or when a note or a start fails. After the first two it starts no conductor
either, since the board was not pulled. It
exits non-zero, naming the check, when main is red or the wait runs out. On a red main it writes the
one-off story `fix-main-<short sha>` (`kind: code`, ready, no epic, the merged story's `repo:`,
`touches: [.]`: the fix may change whatever turns the base green) into
the main checkout's board, where every command reads stories. There it is git-ignored through the
clone's `.git/info/exclude`, as `.gitignore` does `.swarm/`, so it shows in no `git status` and meets
no pull; its builder reads it there and leaves it alone, and reconcile takes it off once its PR
merges. The story names the failed Actions runs and holds the red checks and up to 20 FAIL lines
from their logs, each log read once its run has completed. The code under test writes those lines,
so the story fences them under a line saying to read them as data, never as instructions, with
control characters taken off and each line cut to 300 characters; main-red keeps the whole names.
merge's own `main-ci:` and `fix-main:` lines, and `next`'s why, show them the same way. Those reads stop 10 minutes after the first
(`SWARM_FIX_MAIN_LOG_SECONDS`), however many runs failed, so a slow log cannot hold up the reconcile
that follows; a run gh cannot read stops at once, and the story names each run it could not read,
and why. Once the story is written, merge logs `main-red <sha> <owner/repo> <base> <checks>` (the
repo lowercased), retires an older fix-main story of the same repo and base that nobody has started
(one merge at a time per repo and base does this, under `.swarm/fix-main.<repo>-<base>.lock`, so
two red merges in one merge-queue batch never retire each other's story),
so one fix is built per red main, and prints `fix-main: <checks> on <short sha>` with the same lines.
When it cannot write the story it says so in a line that does not start `fix-main:`, and leaves the
red main and fix before it as they were. A red main clears, logging `main-green` and retiring its
fix-main story if nobody has started it, only on a commit that shows it fixed and has the red
commit in its history (a merge that landed before it, its CI wait ending later, fixes nothing): a later merge into
the same repo and base, or the base's head that reconcile reads (a revert, a re-run), that changes
more than the board's own files (a board-only commit's CI may skip its tests, so a board-only head
is judged by the newest commit before it that is not), has every check, status and workflow run green (a commit with only statuses counts), and has a passing run of each
check that went red, or, when the base requires checks, of each of those (a fix may rename or drop the
failed job; a path filter may skip a check the base does not require). Until then, while the story is buildable (ready, `kind: code`: one escalated or held for the lead goes
to the lead's queue instead) with no build of it, `next` names
`fix-main fix-main-<short sha>` ahead of everything else, a conductor's wait included. Inside herdr it runs only
from a pane this project did not start (the lead's), or from a conductor's with `merge = agent`; a
pane it cannot identify is refused.

The plugin also ships a merge guard, a PreToolUse hook on Bash (`hooks/hooks.json`, running
`hooks/merge-guard.sh`), for every Claude session it is installed in, yours included. Inside a swarm
project (a `.claude/swarm/` folder at or above the session's folder, or above its main checkout when
the session is in a git worktree) it refuses a call that does one of four things: runs gh's merge
subcommand, `gh pr merge`, however its words are quoted; makes the REST or GraphQL merge call, `gh api`
on `pulls/<n>/merge` or a `mergePullRequest` or `enablePullRequestAutoMerge` mutation; holds either
of those in text handed to a shell or an interpreter (`bash -c`, `eval`, `python3 -c`, `node -e`, or a
heredoc, here-string or pipe into one, with a code flag or without) or written to a file; or chains
`swarm.sh merge` to another command with `;`, `&`, `&&`, `||`, `|`, a newline, `$( )` or backticks.
It guards against careless commands, not deliberate evasion: a merge reached any other way, such as
through a variable, a script run by `source` or process substitution, `awk`'s `system()` or an
alias, passes. A command that only mentions a merge passes too: `echo`, `printf` and `grep`, a commit message, and a PR
body given as `--body "$(cat <<'EOF' ... EOF)"`. On a refused call the hook exits 2, the session
sees its reason, and `.swarm/events.tsv` gets an incident line. The guard reads only the command, never
the session's folder or the call's description. Once the command says merge the guard fails closed: if
it cannot run its check (no `python3`, input it cannot read, an error of its own), it refuses the
call. Outside a swarm project the guard allows everything else.

The hook also refuses commands that can lose work. In every session in a swarm project, yours
included, it refuses a `cd <dir>` followed by `;` outside a `$( )`: when the `cd` fails, the rest
runs in the folder the session was in, so write `cd <dir> || exit 1 &&`. A `cd` in the condition of
a `while`, `until` or `if` is not read as one: it passes, and the commands after it are checked
where the call runs. It refuses a `git checkout`
that would overwrite uncommitted changes: unstaged ones, and staged ones too when it checks out from
a commit (`git checkout HEAD -- f`). Back the file up with `cp` and restore from the copy instead.
swarm.sh starts every Claude agent with `SWARM_AGENT` set to its name. In an agent's session the hook
also refuses `git checkout`, `switch`, `restore`, `reset --hard`, `stash` and `clean` in the
project's main checkout, whether the command runs there from the session's folder, after a `cd`, or
through `git -C`. `git stash list`, `git stash show` and `git clean -n` change nothing, so they pass.
It also refuses an agent's `pkill`, `killall`, `kill $(pgrep ...)` or `kill $(pidof ...)`, and a
`kill` of PID `0` or a negative PID (`kill -9 -1` signals every process you own): any of them can kill
another session's process. `kill $!` and `kill <pid>` pass. It refuses an agent's `gh pr checks --watch` and
any `while` or `until` loop around `gh pr checks` (a `while read` loop that checks each PR once
passes), and names `swarm.sh wait-pr`, which stops on a red
check, a conflict or a deadline. A single `gh pr checks` passes.
Your own session has no `SWARM_AGENT`, so only the `cd` and `git checkout` rules apply to it. These
rules fail open: an error in them never refuses a call, even one whose command also says merge, and
a command that says `git` or `cd` but not merge passes when the check cannot run at all.

An agent's guards come from the flags it starts with: `--disallowedTools` (no `gh pr merge`, and for
the fallback reviewer no file tools, commit or push) and `--settings`, which sets `SWARM_AGENT`.
When herdr restarts, it reopens each agent's pane and resumes the session. On its own it would run
`claude --resume <id>` with none of those flags, in the pane's whole environment. So as soon as herdr
has started a Claude agent, before its brief, swarm.sh gives herdr the command to resume it with
(`herdr pane report-agent --source swarm`, with the session id), so a pane whose brief is never
taken up has it too: `python3 -I <wrapper> claude --resume <id>` and
every flag the agent started with. The wrapper, and the command it starts with, are the session's
own, under `~/.claude/swarm-dev/resume/` (`$CLAUDE_CONFIG_DIR/swarm-dev/resume/` when that is set),
so the project's path is never in the command and a later agent of the same name never changes
them. The wrapper keeps only the allowlist the agent started with (§ Building, **The agents'
environment**) and its story's `env:` names, with the restored pane's own values, so no value is
written to disk or put on a command line. It is Python, not bash, so a `BASH_ENV` or an exported
shell function in that pane never runs. It also makes the session's own `ZDOTDIR` afresh, as the
first start makes the agent's, so nothing written there since runs in the restored agent's shells,
and restoring one session never touches another's. herdr refuses a resume command over 64 arguments or 8 KiB
(joined), or with an apostrophe or a control character in it, so swarm.sh checks those before a pane
opens and stops the start, saying which. It also stops on a herdr older than 0.9.2, which takes the
command and drops it. If herdr refuses the report itself, the agent has not had its brief yet, so
swarm.sh closes the pane and fails the start.

The plugin's hooks report an agent's state to herdr: working on each prompt and after each tool
runs (so an answered permission prompt no longer reads as blocked), idle when a turn stops or ends
on an API error, blocked on a permission prompt. Each report carries the resume command again. Only
the pane's own session reports, the one the command resumes. A `claude -p` that an agent runs from
Bash inherits the agent's variables, but its session is a different one, so it reports nothing and
never changes the command. The agent's own `/clear` moves the command to the new session; a nested
session's moves nothing. Each report has a
`--seq` of the time the event happened, taken before herdr is called, and herdr keeps the newest,
whatever order the calls arrive in. When you quit an agent's session yourself, the hooks hand the
pane back to herdr (`release-agent`). A session that ends because herdr restarts keeps its resume
command. Each hook calls herdr in the background, so a herdr that hangs never holds a prompt.

**Moving a running epic to a new version.** A running agent keeps the plugin version it started
on. After `swarm.sh update` (or `claude plugin update`) and a restart of your own session, run
`swarm.sh upgrade <epic>` to move that epic's agents (its conductor, builders and review agents) to
the installed version. `swarm.sh upgrade backlog` moves the backlog conductor and the stories with
no epic, and with no argument it moves every agent the project started. upgrade runs detached
until it is done: it starts itself again under `nohup`, in a process group of its own, and once
that worker holds the project's upgrade it prints the worker's pid and its log,
`.swarm/upgrade-<version>.log`, and returns, so closing the session that started it does not stop
it. A worker that stops first, as one that finds another upgrade running does, has its lines
printed and its exit code returned instead. `--foreground` runs it in your shell instead. One upgrade runs per
project. A second one, while the first runs, prints the running one's pid and log and starts
nothing. It exits 0 when the running one moves its agents too (the same epic, or every agent), and
1 when it does not: `<epic> was not moved; run it again once the running one ends`. A pid file
whose process is no longer a `swarm.sh upgrade` counts as none running. While it runs, `swarm.sh
status` names it, its epic, and that epic's agents not yet on the version it moves them to.
upgrade first checks the
conductor's `env:` names, as `conduct` does; if one is refused, it asks the conductor for nothing.
Otherwise the conductor writes a handover to `.swarm/handover-<epic>-<date>.md` (each open PR with
its review round, what its builder still owes, and findings it has not sent) and ends its turn. A
conductor already on the new version does this too whenever its builders will restart, so it never
acts on one mid-restart. An idle conductor is asked by prompt; a busy one gets a note in its inbox,
which it reads when its wait returns. upgrade works in rounds. Each round reads the agents again,
so one started meanwhile is moved too, and picks up a handover that came late: a conductor's
builders wait while its handover is not written or it is not idle, read again each round, since a
conductor whose turn ended can be woken by a background watch. A conductor that got the request in its
inbox and is idle with no handover is asked again by prompt, and one whose session is gone is named
at once. Each round restarts every builder that Claude Code reports idle, or whose turn stopped on an API
error, reading the session herdr has in the pane now (a `/clear` moves it); herdr's wait only wakes
it to check. Claude Code also reports `busy` for a session whose turn is over but whose background
shells (a `make test`, a `wait-pr`, a conductor's `watch`) still run, so a session reported busy is
read from its log too: when its last assistant entry has ended its turn, with no tool call waiting
for a result and no user entry after it (a prompt, a scheduled one included, or a tool result), it counts as idle and is restarted, its
background commands, subagents and monitors stopped (it is told to start them again). A subagent's own entries in the main log are not the session's turn. A turn still in progress, one
waiting on a tool call's result, one waiting on a prompt, and one whose log cannot be read stay
busy, are never interrupted and wait for a later round. A builder that goes busy between the round's
read and its restart is waited for one round (60 seconds) at most, then waits for the next, so a
round never stalls and the paused conductors' markers stay fresh. One whose session is gone or unknown is named at once and not restarted. A restart
sends ctrl+c twice at once (Claude Code exits only on a second press right after the first) until
claude exits. It then starts claude again in the same pane: a fresh allowlisted environment whose
`PATH` starts at the new version's `bin/` (an older plugin root's is dropped), and `claude --resume
<session>` with the flags its claude ran with (`herdr pane process-info`; the session from `herdr
agent list`), and gives herdr that command, as a first start does, so a herdr restart keeps its
guards. If process-info cannot be read, the agent is left as it is. A resumed session keeps its
context, so only the plugin root changes. Each restarted agent is told the new `swarm.sh` path,
since its brief names the old one, and that the restart stopped its background commands, subagents and monitors (a
`wait-pr`, a `codex-review`), to start again. The conductor goes last, told which builders were
restarted and which were left: restarted and told to carry on, or, if it was already on the new
version or its restart failed before its claude exited, only told to carry on.
upgrade never touches a worktree, so uncommitted and unpushed work stays as it is. When it is done
it prints one line per agent: `<name>: <old> -> <new>`, `<name>: left on <old>: <why>`, or
`<name>: already on <new>` (with a reason, when a conductor already on it wrote no handover: it is
never left, and fails nothing), then `upgrade done: <n> moved, <m> left (exit <code>)`, so a log
that ends without that line was cut off. Only an agent whose version changed counts as moved. The
run is logged as one event, the detached worker's, with its epic as the target. `swarm.sh version` in a pane confirms the version. If a restart
fails from the first ctrl+c on, upgrade leaves the pane open, and the agent's line names the
`claude --resume <session>` that brings it back and the folder to run it in. A conductor that
could not be told to carry on gets a line saying to tell it by hand. A TERM to the run (a HUP does
not reach it: the worker runs under `nohup`) names
each agent it had not moved as left (one cut off mid-restart with its `claude --resume` line), tells
each conductor it paused which of its builders were restarted and to carry on as before, and ends
the log on `upgrade stopped: <n> moved, <m> left (exit 143)`. A KILL or a reboot
cannot, and leaves that conductor waiting for a prompt. An agent that leaves herdr's agent list
before it is moved is named as left, never forgotten; when it is a paused conductor, its builders no
longer wait on it. A session Claude Code reports as unknown (a bad read of its list) waits for the
next round, as a busy one does; only a gone one is left. A run that never reads herdr's list exits
1 and says no agent was moved. upgrade stops when every agent is moved or left,
or after `SWARM_UPGRADE_WAIT_MS` (2 hours, for the whole run). An agent still busy then is left on
its old version. A conductor with no handover by then, or still busy after writing one, is told to
carry on as before: by prompt once it is idle (upgrade waits up to `SWARM_UPGRADE_GRACE_MS`, 5
minutes, more for that), else in its inbox. Its builders are left with it, named for the reason:
their conductor wrote no handover, or wrote one but stayed busy. upgrade exits 1 when any
agent is left; a later run skips the agents already on the new version.

**Merge one at a time, unless the base has a merge queue.** After each merge, merge the base branch into every other open wave branch before
trusting its CI; a branch that conflicts gets no CI at all, which looks like a hang. A merge queue
tests each PR on top of the ones ahead of it, so there every reviewed PR can be enqueued at once.

**Keep with the lead:** real-cloud runs, credentials, and anything that changes permissions.

**Clean up.** After each merge, `swarm.sh reconcile` closes the story's builder if it is open and
removes its worktree and `story/<slug>`, here and on origin (§ Merging). By hand,
`swarm.sh close <slug>` closes a story's pane (its tab, when it was the last pane there) and keeps
its open PR, branch and worktree, putting a `ready` story in review with that PR (`kept:`). `--drop`
clears them on a `ready` story, one in review, or a held child (`blocked` with `held_by:`) whose PR
is open (§ Model and effort); on any other story it prints `not dropped:`.
`swarm.sh close conduct-<epic>` closes the epic's tabs. herdr closes a tab without asking, so close
first checks each tab's panes. It keeps a tab that holds an agent that is working or waiting, or
whose story has an open PR, and it keeps one when it cannot read an agent's state or gh cannot list
its PRs. It prints each of those agents as `kept`, and still closes the conductor's own pane.
`swarm.sh close <name> [cause] [--drop] --all` closes the kept tabs as well.
close takes the full recorded name. It closes only what `.swarm/state` records under exactly the
name you give it: its pane, its tabs, and for a conductor the tabs of its epic, which its brief or
its full name gives. herdr and `swarm.sh` print agent names cut at 32 characters, so two long names
can look the same, and a cut name matches no record. herdr's agent list stands in for a missing
record only for a name shorter than 32 characters, which herdr holds exactly. When nothing is
recorded under a longer name and herdr lists a live agent under its first 32 characters, that agent
may be another's. close then closes, counts, clears and keeps nothing, and fails: close by the full
recorded name, or close that pane by hand if it is the one you meant. With nothing recorded and
nothing live under the cut, there is nothing to close by mistake, so the close goes on with no
pane, as it does for a pane closed by hand.

## Releases

No story PR bumps `.claude-plugin/plugin.json`. Once main has changes since the last
release, `swarm.sh next` prints `release`: the project has `.claude-plugin/plugin.json`, the tag
`v<version>` for its version is on `origin/<base>`, and a commit since that tag changes a file
outside the board. It reads local refs only, since reconcile has just pulled. The lead opens a PR
from `release/v<new>` that bumps only that file, to the next minor version (a patch when every
change since the tag is a fix), and lists the PRs merged since the tag. Before it cuts that branch, the lead lands a docs PR that covers
every behaviour change since the tag, and the release PR names it. When nothing since the tag
changes what a user runs, sees or has to do, a `Docs: none — <why>` line in the release PR body
stands in for the docs PR. With `merge = agent` the
lead merges it with `swarm.sh merge --release` and checks that the tag and the GitHub release
exist. With `merge = human` it waits on your merge.

Once a release merges, `merge --release` reads its merge commit's first parent through gh, for 30
seconds at most. If that is not the base the release check last read, a PR landed between that read
and the merge, and the release shipped commits no check read. merge then prints `warning: <merge
commit>'s first parent is <sha>, not <sha>, the base the release check read, so it ships <commits>
unchecked` and logs it as a `merge` line in `.swarm/events.tsv`, whatever the repo and whatever CI
on the base says. When gh can't read the parent, it warns the same way.

When the release is swarm-dev's own (its repo is the GitHub repo named by `repository` in the
plugin's `plugin.json`; otherwise merge prints a line saying it skipped this step), `merge
--release` also updates the plugin and moves the agents onto it, once CI on the base is green. After
that warning it updates nothing, and prints `refused: the release ships commits no release check
read, so the plugin was not updated`, followed by what to run once they are checked. Otherwise it
waits up to 10 minutes (`SWARM_RELEASE_WAIT`) for the tag `v<new>` on the merge commit, or on a
later commit of the base, and a published GitHub release. Then it runs `claude plugin marketplace
update swarm-dev` and `claude plugin update swarm-dev@swarm-dev`, 5 minutes at most each. Once the
new version's `swarm.sh` is in the plugin cache, it runs that version's `swarm.sh upgrade`
(detached) in every swarm project where herdr runs an agent, and prints each upgrade's log path;
each one gets 2 minutes to start its worker. The old version's `bin/` is taken off that upgrade's
PATH, so each agent it restarts finds the new `swarm.sh`. An agent's project is the `SWARM_PROJECT`
its restore wrapper sets, so a builder of an external board counts; with no wrapper, it is the
project its folder is in, and with no agent in herdr's list, or a list it can't read, this project,
with a warning saying why. Last, it asks you to restart the lead session (`/exit`, then `claude
--continue`) in this project and in every project it found. The update is global, Claude Code loads
a plugin's hooks only at startup, and until a lead restarts, the `swarm.sh` on its PATH is the old
one. When CI on the base is not green, the release can't be confirmed or the update fails, it prints
a warning naming the new version's `swarm.sh upgrade` to run once the plugin is updated, and
upgrades nothing. An upgrade that fails, takes too long to start, or finds another upgrade already
running in its project and starts nothing gets the same kind of warning, and merge moves on to the
next project. The release still counts as done, and neither these warnings nor the refusal above
changes merge's exit code.

## Commands

| Command | What it does |
|---|---|
| `/epic <title>` | Write a draft epic with a co-author agent; it is planned once you agree it. |
| `/swarm-dev:swarm` | Run everything after the design, stopping when a decision is yours. |
| `swarm.sh init` | Set a project up, from its git root: the board templates, `.claude/swarm/` with a commented `commit_trailers` line, the `.gitignore` lines, a `ci.yml` that runs `make check` on each PR and on pushes to origin's default branch, and fails when make has no `check` target, with a gate (`.github/swarm-board-only.sh`) that skips a PR or push changing only the board's own files (with workflows already there, it writes the gate and prints the step to add; a board outside the repo gets no gate; when origin's default branch can't be found, no CI), and a pre-commit hook that runs `make check` except on a commit that changes only the board's own files (when a hook exists or `core.hooksPath` is set, it writes none and prints the lines to add before any `exec`, or, for a global `core.hooksPath`, says to add them nowhere there). It ends by listing the files it wrote that git does not track yet, to commit. A second run changes nothing. |
| `swarm.sh status` | Show agents that need a look, stacked builds whose parent moved or merged, what waits on you, and what runs next. |
| `swarm.sh dash --watch` | Open the live dashboard: a running-now box, how long each working agent has gone without a sign of life, how long each running codex review has run, and a merges-per-day speedometer with two warning lights, and a third when someone had to step in. `swarm.sh dash --project <dir>` (repeatable) draws several projects. `swarm.sh dash --check` compares each figure with the command that owns it and exits 1 naming each one that differs. With `lead = session` in the config, only your own steps say needs you; the rest goes in a lead's queue ([details](dash.md)). |
| `swarm.sh upgrade [<epic>\|backlog] [--foreground]` | After a plugin update, move a running epic's (or the backlog's) agents to the new version: its conductor writes a handover, then each agent, once idle, restarts in its pane with `--resume`, keeping its context. It runs detached, in rounds, until every agent is moved or 2 hours pass, logging to `.swarm/upgrade-<version>.log`; one runs per project. It prints each one's old and new version and never touches a worktree. |
| `swarm.sh conduct <epic>` | Start a fresh conductor for one epic. `swarm.sh conduct --backlog` starts one for the ready stories that have no epic. `watch --backlog` follows their PRs. |
| `swarm.sh wait --until-report conduct-<epic>` | Wait, with no timeout, until an epic's conductor writes its report, waits on a prompt, exits or needs a login. `/swarm-dev:swarm` runs it for you. |
| `swarm.sh wait --lead` | Wait until the lead's queue gains a held or escalated story, or a green PR in review that waits on you, and print each new one. |
| `swarm.sh wait-pr [--timeout <seconds>] <PR URL>` | Wait for the checks on a PR's head and print the head SHA and each check. It exits 0 when all are green and 1 on red. It exits 2 when gh fails (a dropped connection, timeout or rate limit is retried first, up to 3 times in a row), at once when the PR conflicts with its base (`conflicts with <base>: merge origin/<base> in, then push`; GitHub's `UNKNOWN` on an open PR, still computing, is read again each poll, with the checks read beside it), when no check run appears within 5 minutes of the first read that found none (`SWARM_WAIT_PR_GRACE`), and when it is still waiting after `--timeout` seconds (30 minutes by default, `SWARM_MERGE_CI_SECONDS`), naming it; a read that hangs ends there too. Exit 1 always means a red check: any other failure, a bad config line included, exits 2. The first rate limit that comes while the budget it came from (GraphQL's for a `GraphQL:` error, else REST's) is spent is not retried that way: wait-pr prints `rate limited: GitHub's API budget resets at <time>; waiting until then`, waits until that time, moves its deadline back by the same amount, and starts its count of retries over. With `--timeout`, a reset past that deadline ends the wait at once, naming the reset time. A rate limit while the budget is not spent is GitHub's secondary, per-minute limit, sometimes in the same words. It is retried after the retry pause plus up to half again, so waits started together spread out, and the budget is not read again once the one reset wait is spent or the error says `secondary rate limit`. The no-check grace moves with the reset wait. It polls every 20 seconds (`SWARM_MERGE_POLL`), so run it in the background. |
| `swarm.sh review-agent <slug> <PR URL>` | Start a read-only review agent for one story's PR, scoped to its `touches` and **Done when**. It writes `.swarm/reviews/<slug>.md` and returns at once; conductors run it for each green PR. |
| `swarm.sh story [--strict] <slug>` | Build one story. It warns when an open story of another epic touches the same function or file; `--strict` refuses instead, and conductors always pass it ([details](method.md)). |
| `swarm.sh merge <PR URL>` | Merge a green PR whose story is in review, pinned to the head that passed, then wait for CI on the base branch and take the story off the board. With `merge = human` the lead runs it only for a PR whose agreed HLD grants `merge`, and you merge the rest. `swarm.sh merge --release <PR URL>` merges the lead's version-bump PR, which changes only `.claude-plugin/plugin.json`, and refuses it while the code changed since the last tag and the docs did not, unless its body has a `Docs: none — <reason>` line. With `merge = human` it merges only when at least one story merged since the last tag and every one of them is under an agreed HLD that grants `release`. `--board` refuses a board PR that sets an epic `active` with no ticket (the epic guard, [§ Merging](#merging)). Where the base has a merge queue, `merge` enqueues the PR. If CI on the base goes red on a commit it merged, it writes a `fix-main` story ([§ Merging](#merging)). |
| `swarm.sh step-up <slug> <trigger>` | Close a struggling build and start the next model in `escalate_ladder` on the same branch, without counting an attempt. `<trigger>` is `findings-<step_up_findings>` (`findings-3` by default), `ci-red-2`, `stalled` or `no-pr`. `swarm.sh step-up --resume <slug>` starts a rung whose start failed. Refused while the ladder is empty ([§ The escalation ladder](#the-escalation-ladder)). |
| `swarm.sh board-pr start\|open\|done <name>` | Make a board edit in its own worktree (`<repo>-wt/_board-<name>`) and open it as a PR. It refuses a change outside the board, and never touches the main checkout. The lead runs it for each board edit. |
| `swarm.sh finish <slug>`, `swarm.sh drop <slug> <reason>` | Take a merged story or epic (or, with `drop`, an escalated story) off the board. On a board in the repo it deletes the file in the board PR `finish-<slug>` (or `drop-<slug>`), never in the main checkout, and prints the `swarm.sh merge --board <url>` that lands it. On a board outside the repo it deletes the file where it is. |
| `swarm.sh grants <story \| epic \| PR URL>` | Print the agreed HLD over a story or epic and its grants, one per line, or `none`. A story goes to its `epic:`, then each `parent:`, up to the first epic with `hld:`; a draft or superseded HLD, a missing one, a missing epic, a story with no epic and a `parent:` cycle all give `none`. A name that is no story or epic but an HLD in the board's `hld/` is that HLD: an agreed one prints itself and its grants, any other gives `none`; a story or epic of the same name wins. A story PR is its stories' (their `prs:` lines); a board PR is the epics and stories it touches, each as the board has it and as the PR's head has it, and a PR that touches `.claude/`, `.github/`, `hooks/` or a root `Makefile`, `GNUmakefile` or `makefile` (in any repo, since each changes what checks a merge or what the agents may do) or the board's `hld/`, or a PR no story lists that touches anything but the board's epics and stories, gives `none`. /plan-hld's board PR is the exception: a PR that modifies one agreed HLD, setting or keeping its single `planned: YYYY-MM-DD` line and changing it otherwise only after its last `## Epics` line, and adds at least one epic and changes nothing else, each epic under that HLD at the PR's head, is under that HLD, with the grants of the board's copy. The HLD's last section must be `## Epics`: after that line, both the board's copy and the PR's may hold only blank lines and list items whose whole content is one markdown link to an epic file in the board's `epics/`, or to one the PR adds, with the epic's slug as the link text. Without the `epics` grant each added epic must be a `draft` at the PR's head. Deleting the HLD, or any other change to it, gives `none`. Items under two HLDs give `none`. A grant other than `epics`, `stories`, `merge` or `release`, a `[` with no `]` on its line, or a `grants:` written as a YAML block list, stops it with the HLD's file and line. `/plan-epic` runs it before asking, and skips the question when it lists `stories`. |
| `swarm.sh plan-unasked [--declined] <epic>` | Record, in board state, that a `later` epic `next` offered (its dependencies done) has had its unasked plan. The lead runs it before that `/plan-epic`. `next` offers the epic no more. The gate lists it as planned unasked on that date: with no stories yet, run `/plan-epic <epic>` again if that plan stopped; with stories, set it `active` to start it. With `--declined`, the user declined the plan, and the gate says that instead. |
| `swarm.sh log-finding [--declined <reason> \| --filed] [--reviewer <who>] [--round <n>] <kind> <PR URL> <text>` | Log a review finding by kind. `--round <n>` records the review round it came from (0 for a plan or board PR). `--declined <reason>` records one that was declined (`out-of-scope`, `nit` or `wrong`). `--filed` records that the lead filed a declined out-of-scope finding as a story, so `swarm.sh next` stops offering it; no report counts a filed row. The reviewer is codex, fallback, code-review, ci, conductor, lead, skeptic, critic, split-critic (the check on a large epic's split), or escaped for a defect found after its PR merged; a gap in a split that a later plan or build finds is logged `--reviewer escaped split-gap` against the split's board PR. |
| `swarm.sh intervene <kind> "<one line>"` | Log a time a person had to step in: `lead-hand` (the lead acted by hand where a command should have) or `user-caught` (the user found a problem first). It writes one `incident` line, which `flow`'s `incidents` section and dash's interventions light count. |
| `swarm.sh hold <slug> <why>` | Log that a conductor held a ready story back this wave, and why: what it clashes with (a story or PR) and the shared files, or the other reason (the give-up rule, closed this wave, `not held:`). It writes one `hold` line, target the slug, outcome `ok (<why>)`. It dies, writing nothing, on a slug that is not a ready story on the board, and on one whose PR was closed unmerged (its last event is reconcile's reopen): that story is the lead's, and a `hold` line would drop the mark `unblock --startable` prints for it. The conductor runs it for each `startable:` story it does not start, other than a closed-unmerged one: at most once per wave for a story, and in a later wave only when the reason changed. |
| `swarm.sh outcomes` | One row per build: model, cost and tokens by type, review rounds and other tells, its epic, whether its PR and its story merged and when, findings fixed and declined by reviewer, when it started, why it was last closed, its escalation steps, and minutes from start to PR and from PR to merge. Once a story is finished (its file is off the board, every PR is merged or closed, and every check on them has finished), its PRs are read from gh once and kept in `.swarm/outcomes-prs.tsv`. `flow` and dash's ci line then read them from there instead of asking GraphQL on every run; `dataset` reads them there too, but still lists each merged story's PRs with gh itself. The cache is keyed by the story's newest build, so a rebuild reads gh again. A cache that cannot be written is said on stderr and the report still prints. |
| `swarm.sh dataset` | Write `.swarm/dataset.jsonl`, one JSON line per merged story. Each line holds the story as the board PR merged it (text, kind, risk, touches, `depends_on`, `estimate_lines`, `easy` and the planner's model), and what happened: diff lines and files of its newest merged PR (the story and epic files left out), builds, findings rounds, fixed findings, rework within 7 days on any of its PRs (`outcomes`' rework column, which flow's `model_fit` reads too; null when `outcomes` could not judge one of its PRs, or one merged in the last 7 days), cost, minutes from start to merge, every model that built it and each escalation with its trigger. `was_easy` is true when the story merged on its first build with at most one findings round, no rework and a diff under 100 lines (`was_easy_rule: 1`), and null when an unknown diff or rework is all that could decide it. Nothing from the environment or the transcripts goes in. A story whose repo cannot be found, or whose PRs `gh` cannot read, is skipped and keeps its line from the last run, and so does any story the run does not read, so the file never loses a story. When `gh` itself is down (`gh auth status` fails) or the logs cannot be read, it stops and leaves the file as it was. |
| `swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>] [--no-cache]` | The project's numbers, a section each: `ci_health` (median CI minutes per PR head, red runs per PR and flakes, and the test files that failed in a rerun that went green), `cost` (where the tokens went, with a row for the lead's own sessions), `epic_totals` (each epic's cost, start-to-PR and PR-to-merge minutes, and the share of its PRs that needed main merged in, beside the 55% baseline), `features` (each feature in `docs/features.tsv` against its metric and baseline, with the ones nobody uses or measures flagged for deletion), `gh_calls` (gh runs per hour by agent role and by subcommand, GraphQL and REST apart, with the paginated and watching runs that spend many requests, and each hour's share of the 5000, from the gh shim's `.swarm/gh-calls.tsv`), `holds` (one row per hold of a ready story: its epic, the first hold's reason and the minutes until its next build started, or how it ended with no build (`dropped`, or `removed` once its story file left the board), or `open`; then the built holds' minutes per reason class, `clash` when the reason names a PR or a hyphenated story that had started by then, `other` for anything else, give-up, closed this wave and `not held:` included), `idle_slots` (per epic, the minutes a story sat ready with no build and nothing it clashed with running, while its conductor ran and while none did, and the most ready at once), `incidents` (incident lines per day and kind, then API-error and auto-mode stops per epic), `lead_queue` (per day, the median and longest wait on the lead, and what still waits), `merge_ins` (why PRs merged main in: a conflict, a clean merge while behind, or neither, with the files conflicts hit most), `merges` (the stories finished per day, which dash's speedometer shows), `model_fit` (cost against results per model and story class, and builder subagents' share of build cost), `predictions` (per planner model, the precision and recall of `easy` against `was_easy`, and how many lines its size estimates were off by, from `.swarm/dataset.jsonl`), `review_loops` (per story PR, each review round's builder model, minutes, findings fixed and declined and step-up, how its loop ended, and totals for tuning the stop and escalation rules), `reviewers` (findings each reviewer raised per kind, fixed or declined, the split critic's fixes beside the split-gaps it missed per split, review rounds per PR, and once findings carry `--round`, each round's yield and the round each story's review stopped in; `--epic` counts only that epic's PRs and lists them), `test_runs` (local `scripts/test.sh` full runs by how many ran at once, the larger of the count at the start and at the end, with the median and p90 seconds and the median load at the start, and the 5 slowest; then builders' runs on `story/*` branches of every filter, with their median and p90 seconds; from `.swarm/test-runs.tsv`), `throughput` (builders at once, stories per chain, review wait and stacked starts, per epic) and `time_in_state` (hours per epic in each state: held ready before a build, building, CI, review wait, fixing and merge wait, with each one's share, largest first, then the median and p90 minutes from a story going ready to its build starting). |

## Cleanup, escalation and session logs

Every agent is a full Claude Code session, on a model chosen by its role, and planning one epic
on the full path (not the small path, which starts none, nor a split, which starts a split-critic) starts four agents, plus up to five skeptics, one per `risk: high` story, and two more surveys for a multi-repo epic. Agents use your own `claude`, `codex`, `gh` and `git` logins and never
touch real cloud or credentials. By default no agent merges; with `merge = agent` only the conductor
does.

When `swarm.sh close` closes the builder of a code, docs or chore story that is still `ready`, it
counts a failed build in the story's `attempts:` and clears the attempt away: its worktree and its
`story/<slug>` branch here and on origin. While the story's PR is open it does neither: it closes the
builder alone and puts the story in review with the PR, unless it is `swarm.sh close <slug> --drop`,
which also closes the PR unmerged and prints the head SHAs it dropped. `swarm.sh reconcile`
removes the same worktree and branches once a story's PR merges, closing its builder first if it is
open. When a PR closes unmerged, it removes them only if no builder is open. That leaves nothing to
clean up by hand, unless reconcile prints `build kept: <slug>` or `build cleared: <slug>`, which say
what is left. A story that has failed
twice is rebuilt on Fable, the most expensive model. This ships on as `escalate_after = 2` in `.claude/swarm/config`;
`escalate_after = 0` turns it off. If the Fable build fails as well, the story becomes a `lead`
story and the lead decides: it re-scopes the story and runs `swarm.sh reset <slug> <reason>` to build
it again (once per story), or drops it. Then it tells you what it chose and why. A Fable build
can stop to ask your consent to spend usage credits. The conductor accepts it for you, so a third
build can spend Fable usage credits. `swarm.sh dash` shows who is on call, how many builds
escalated today, which attempt each Fable builder is on, and each escalation step in the recent panel.

### The escalation ladder

A step-up keeps the work done so far, where `escalate_after` clears a failed attempt away and the
next build starts from the base. With `escalate_ladder = sonnet,opus,fable`,
`swarm.sh step-up <slug> <trigger>` closes the story's builder without counting an attempt and starts
the ladder's next model in the same worktree and on the same `story/<slug>` branch, with any open PR
left as it is. The trigger says why: `findings-<step_up_findings>` (that round of review findings, `findings-3` by default), `ci-red-2` (CI
red twice), `stalled`, or `no-pr` (the builder stopped with no PR). The build is the newest
agents.tsv line for its builder, and the next model is the ladder's first one above that build's
model, so a chore on Haiku steps to the first rung. The new builder keeps its build's role family. On
the escalate role's model (Fable) it runs as `escalate`. Otherwise a code build runs as `code-sonnet`
on Sonnet and as `code` on Opus, and a docs or chore build keeps its role, and that role's effort, on
the new model. `escalate_ladder` changes nothing about `escalate_after`: a step-up counts no
attempt, while a close that counts a build as failed raises `attempts:` and clears the build as
before, and the next `swarm.sh story` build is on Fable once `attempts:` reaches `escalate_after`.
The Fable rung is an `escalate` build, though, so a close that counts it as failed hands the story to
the lead, as after any failed escalate build, whatever `attempts:` says.
Nothing is closed when the ladder is empty, when the build is at or above the ladder's top rung, when
the story is not `ready`, not of a kind an agent builds, held for review as a stacked child
(`held_by:`), or has no worktree, when a PR on `story/<slug>` has merged or is set to auto-merge (the
build is done, as `close` also judges), when gh cannot list those PRs, when its `env:` names a
variable not set here, or when the build's role is one nothing starts now (a past `verify` build).

The old builder is closed first, since the new one takes its name, and only then is the handover
brief written, so it holds everything the old builder did. If closing it left a git step unfinished
in the worktree (an `index.lock`, or a merge, rebase, cherry-pick or revert in progress), step-up
stops and names it: finish or abort it there, then resume. If the start fails, step-up stops at the
step that failed, with that step's message, and logs nothing as an escalation. A builder's
brief is sent at most twice, and a Fable builder, which at xhigh can take longer to start, gets 300
seconds over both tries to show it took it (150 for its one try when it has no Claude session to
read yet, see `tell`); `SWARM_PROMPT_TIMEOUT_MS` overrides that.
When a new rung's brief may have gone out but still reads as not taken up, or unsure, or herdr sent
it once and did not show the turn start (the start's warning), step-up keeps
its pane, warns, and reads it once more over 300 seconds, then says `took up its brief after all`
if it did. A builder blocked on a question before its brief went is not read again. If herdr gives
no status for it during that read, step-up stops and keeps its pane and agents.tsv line: look at it
with `herdr agent read <name>` before you resume. One still idle
with no turn after that, or gone, has not started: it is closed and loses its agents.tsv line, so
the rung is on record once, when it starts. The worktree, branch and step-up marker are kept, and
`swarm.sh step-up --resume <slug>` writes the brief afresh and starts the rung once the cause is
fixed. A resume that starts logs the step-up and sends the `/goal` as step-up would have.

The new builder's brief is the usual one with a handover after it. The handover says why it took
over, and gives the story as the board holds it, since the last builder may have deleted the file
from its worktree. Next comes the diff: committed and uncommitted changes and untracked files, from
the build's merge-base with the base, so the base's newer commits are not in it. It stops at 400
lines, and the fence around it is longer than any run of backticks inside it. For a story stacked
on parents whose PRs are still open, the diff starts at their branches instead, and the handover
carries build_story's `Merge after <PRs>` note. When a parent's PR has merged (squashed, its commits
are on the base under other ids), the diff is of `origin/<base>` to the branch as if the base were
merged in, and the handover says to merge it in before pushing. If that merge would conflict, the
diff stays the one from the merge-base, with the parent's commits in it, and the handover says to
merge the base in and resolve it first. Then come the review agent's findings from
`.swarm/reviews/<slug>.md`, pasted only when their `head:` line is the branch's HEAD. Findings of an
older head may be fixed already, so the handover only names the file. Last come the open PR's
failing checks. With none listed, it says that none are failing, that the PR has no checks
reported, or that gh could not read them. The handover also tells the builder to put a `Models:` line in the PR body naming
every model that worked on the story, in order.

You rarely run `step-up` yourself: with the ladder set, swarm.sh runs it on each trigger as it sees
it. A build here starts at the story's newest `story`, `escalate` or `agent` start.

- `close` steps up a builder it closes with no PR (no cause, `met` or `bound`) instead of counting
  an attempt.
- `wait --stall` steps up a builder it finds stalled, and prints `stepped up:` in place of
  `stalled:`.
- `tell <slug> findings` steps up a builder on its `step_up_findings`-th findings of the build (the third by default) or any after, and
  does not send them: they go into the handover brief, and the tell fails, saying so. An earlier
  tell counts when it went through, or when herdr sent the findings but the builder was not seen
  taking them up. That tell fails and says what to do. When the builder may or may not have the
  findings, do not send them again. When herdr read it idle with no turn after both tries ("not
  taken up"), read its pane, and if they never arrived send them again as `tell <slug> nudge`, which
  is not a round. One herdr never sent, or whose reply could not be read, does not count. Instructions
  that are not review findings, such as a stacked child's merge, go as `tell <slug> nudge`.
- `tell <slug> findings` holds the story for the lead when its builder is on or above the top rung,
  where no step-up is left, and the tell would be the `top_rung_rounds`-th findings round there (the second by default) or a later one (the
  block, the `held` line and the tell's message name the round). The rounds count from when
  the builder reached that rung, or from the build's start when it began there (an `escalate_after`
  Fable build, or the top of a two-rung ladder), or from the lead's last `reset` of the story,
  whichever is latest. The findings are not sent and the tell fails, saying so. The story turns
  `kind: lead` with `held_for: top-rung`, logged as `held`, and its block holds the findings, which
  are also kept in `.swarm/briefs/<slug>.held-findings.md`. The builder and its PR are kept. The lead
  narrows the scope, splits the story or accepts the PR with follow-ups, then lifts the hold with
  `reset` (which keeps `attempts:` and is not the story's one reset) and sends that file with
  `tell <slug> findings`; that tell counts like any other, so a later round holds the story again. Or
  the lead drops the story: `drop` leaves the builder, PR and worktree, so the block says how to close
  them first. A tell to a story already held is refused. A hold that fails after its block is written
  fails the tell, and the findings are not sent. Where a
  step-up would be refused (the story is not `ready`, is a held stacked child, or has a PR merged or
  set to auto-merge), nothing is held and the findings go as usual.
- `watch --epic` or `--backlog` steps up a story of its own whose builder is open, once the PR has
  gone red on two heads of the build. Every head it sees goes into `.swarm/red-heads.tsv`, and each
  is judged again on later polls until `ci_gate` calls it red or green, even after a new push. A
  head that was already there when the build started is not counted. The lead's bare `watch` steps
  up nothing.

Each prints `stepped up: <slug> ...`, and the conductor's brief tells it to wait on that builder
again, not to close, retry or tell it. A close that a step-up replaced logs no close: the escalate
line ends that build. One step-up of a story runs at a time, under `.swarm/locks/step-up-<slug>`, which a
top-rung hold takes too. No step-up is tried at the top rung or off the ladder, so the command
carries on as it would with the ladder empty, apart from the top-rung hold above. A step-up that is refused, or fails before it closes the builder, says why on stderr,
logs nothing (a refusal is no sign of life), and leaves the command to carry on the same way. `watch`
does not try it again on the same head. A step-up whose new builder does not start, after the old one
closed, prints `step-up failed: <slug>` and stops the command that ran it: a close counts nothing
and clears nothing. The story is then the lead's to resume (`step-up --resume`), and no trigger tries
that build again meanwhile.

A step-up is logged as `escalate` with `ok (<trigger>: <from> -> <to>)`. Only a step to the
escalate role's model starts an escalate build, so `outcomes` pairs only those (and build_story's
`ok (attempt N)`) with an escalate build, and `dash` counts only those among today's escalations. A
Fable builder that got there by a step-up shows `from <model> · <time>` in `dash` where a third
build shows its attempt, and `dash` times each rung from its own step-up. In `outcomes` a
target's step-ups, in order, take its builds in agents.tsv order. The rungs of one build are one
attempt, and each replaced build has a close, with the cause `step-up:<trigger>`.

`swarm.sh close` keeps a copy of each closed agent's session log in `.swarm/sessions/`, because
Claude Code deletes them after 30 days. The copy is not redacted, so it can hold secrets the session
saw. Only your user can read it, and `.swarm/` is git-ignored, so it never leaves your machine.
Flow's `cost` section and `outcomes` read the copy once the original is gone.

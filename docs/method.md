# The method

Work is planned top-down, the user approves each level before the next is made, and every agent
at every level runs in its own herdr pane so it can be watched.

## The planning chain

1. **HLD**: `/hld <title>` opens a pane on the most capable model, where the user writes
   `docs/hld/YYYY-MM-DD-<slug>.md` with it. A reviewer attacks the draft before it is `agreed`
   (§ Writing the HLD).
2. **Epics**: `/plan-hld <hld>` runs a swarm that splits the HLD into epics, each with a
   **Done when** that could fail. Skeptics and codex check for gaps and overlaps.
3. **Stories**: `/plan-epic <epic>` runs a swarm that splits each epic into one-PR stories.
4. **Build**: `swarm.sh conduct <epic>` hands the epic to a fresh conductor, which builds its
   `ready` stories in parallel panes and merges them.

`/swarm-dev:swarm` runs the chain after the HLD (on an empty board it explains the flow instead): `swarm.sh next` reads the board and names the next step,
`/swarm-dev:swarm` does it and loops, stopping only at an approval, a draft HLD, a `lead`
story, or a `later` epic. The board is the only state, so a run can stop anywhere and the next
`/swarm-dev:swarm` continues. Building comes first (a conductor still working, then an active epic's ready
stories, then one-offs), then planning (an active epic with no stories, then an agreed HLD with
no epics). An epic is planned only once every epic it `depends_on` is done, so its stories are
scoped against code that exists.

A story the swarm must not build says so with `kind: lead`: the lead runs it, and any step that is
the user's is marked **You:** in it (§ Who does what). An open question for the user is a `lead`
story too, so the board's **Waiting on you** view lists it. An epic is done
when its last story's PR deletes the epic file and marks it done in the HLD's `## Epics`.

The session that runs the chain supervises, reviews and merges; it does not do the agents' work.

## Who does what

Three parties do the work, and which one does each step is decided when the work is planned,
not found out while building.

- **You** agree the HLD, approve the epics and the stories, merge PRs (with `merge = human`), say go
  before each `lead` story, and do its **You:** steps.
- **The lead** is your own Claude Code session, the one you run `/swarm-dev:swarm` in. It supervises,
  reviews, and runs `lead` stories while you watch: they touch real cloud or credentials, are hard
  to undo, or need a step from you, so they need your logins, your go-ahead or your hand.
- **Agents** plan, conduct and build everything else, each in its own pane; builders also get
  their own worktree.

The lead's messages to agents go through `swarm.sh tell`, which logs them as `tell:<kind>`, never a
bare `herdr agent prompt`.

A story is `kind: lead`, never an agent's, when it:

- changes real cloud, uses credentials, or changes permissions;
- is hard to undo (deletes data, turns something off, a production change): its **Done when** names
  your go-ahead;
- needs a person: a decision, a portal click, another team's approval, a hand PR, a network only
  you can reach. That step is a **You:** line in the story. The lead does the rest around it: it
  prepares the PR or the request, and checks the result after.

A merge is never a story of its own: with `merge = human` every merge is yours already. A `kind`
that is none of code, docs, chore, verify or lead (a typo, or `operator` from older boards) is
never built: `swarm.sh` stops and names it.

**Planned up front.** `/plan-hld` writes each epic's **Your part**: the human steps it expects.
`/plan-epic` turns them into `lead` stories, and its report ends with **What you will do**, so
you see your share of the work before you approve it. A step found during the build that needs
you is a new `lead` story, added to the board, not done quietly.

**Every stop names its exit.** A `lead` story says what it needs from you (a go-ahead, a login, a
network) in its body, and each **You:** step says how the lead learns it is done (you tell it, or
it sees the merge). A status or flag raised for you says who clears it and how.

## Writing the HLD

Everything starts here, and it is the one stage you do by hand: the HLD decides what every epic,
story and line of code after it is for, so it is written with you, not for you.

1. **Start it.** In your Claude session, inside herdr: `/hld <title>`, for example
   `/hld Add rate limiting to the API`. This creates `docs/hld/YYYY-MM-DD-<slug>.md` from the
   template with `status: draft`, and opens a new pane (tab `hld`) with a co-author on the most
   capable model. Your session only supervises from here.
2. **Write it in the co-author's pane.** Switch to that pane and talk to it there. It reads the
   code, the ADRs and `AGENTS.md` first, then asks you the questions that decide the design, one
   or two at a time, and writes your answers into the file section by section, citing evidence.
   It does not invent requirements, commit, or change `status`.
3. **Say it is ready**, to the co-author, in the same pane. A reviewer (the most capable model, at
   `xhigh` effort) starts on its own and attacks the draft: goals that cannot be verified, a
   design that contradicts an ADR or a safety rule, missing alternatives, unnamed risks, open
   questions that would block splitting it into epics. Its findings arrive in the co-author's
   pane; go through them there and revise until you are satisfied. You never switch tabs.
4. **Agree it**, to the co-author. Your session, waiting in the background, sets `status: agreed`,
   opens a PR for the HLD (reviewed like any other change), and closes the co-author's pane. Only
   you can agree an HLD; no agent changes its status.
5. **Hand over.** Run `/swarm-dev:swarm`. It sees an agreed HLD with no epics and starts `/plan-hld`.

**What a good HLD has.** The template's sections: Problem (with evidence), Goals, Non-goals,
Current state, Design, Alternatives, Risks and safety, Rollout, Open questions, and Epics (filled
in later by `/plan-hld`). The ones that matter most downstream: **Goals** that could be checked
and fail, because each epic's **Done when** comes from them; **Non-goals**, which keep the
decomposition from growing; **Rollout**, which becomes the order of the epics; and **Open
questions**, which must be answered or explicitly deferred before the HLD is agreed.

**Stopping and resuming.** The HLD is a file, so nothing is lost if you stop: run `/hld` on its own
(or `/swarm-dev:swarm`, which sees the draft) and a new co-author picks up the draft in progress from the
file; if there are several, it asks which. With no draft at all, it tells you where the chain
stands instead. To
replace a design later, write a new HLD and set the old one `status: superseded`.

## The board

The board is files: `docs/hld/`, `docs/epics/` and `docs/stories/`, one file per item, with front
matter the scripts read. There is no shared board file to conflict on; the PR that finishes a story
deletes its file (or, with `finished = mark`, sets it `status: done`), and the PR is the record. A project can move the board and change how finished
items leave it (§ Configuring a project). `templates/docs/` holds the READMEs that define
each format and two Obsidian Bases (`Board.base`, `HLDs.base`) that show the board as a view.

## Configuring a project

`swarm.sh init`, run from the project's git root, copies the board templates into `board_dir`
without overwriting a file, creates `.claude/swarm/`, and adds `.swarm/` and the board's Obsidian
lines to `.gitignore`. The next `/swarm-dev:swarm` asks once for the brief (`.claude/swarm/brief.md`) and writes
only what the user says; an empty file means they declined.

`.claude/swarm/config` holds `key = value` lines and `#` comments. The script parses it and never
runs it; an unknown key or a bad value stops `swarm.sh` with the file and line. `swarm.sh config`
prints every setting and where it came from.

| Key | Default | What it does |
|---|---|---|
| `board_dir` | `docs` | where the board is, relative to the project unless absolute |
| `repos_dir` | the project's parent | where a story's `repo: <name>` is found |
| `base_branches` | origin's default branch | branches to try, in order, as the base: `dev main` means `dev` where origin has it, else `main` |
| `finished` | `delete` | `mark` keeps a finished item on the board as `status: done` |
| `merge` | `human` | `human`: no agent merges, and a green, reviewed PR waits for you (§ Merging). `agent`: the conductor merges |
| `merge_admin` | `false` | `true`: `swarm.sh merge` passes `--admin`, which bypasses every rule on the base branch: required reviews and the rest as well as required status checks. `merge` re-checks only the status checks (each one the base's rulesets or branch protection require must have passed on the head), and nothing checks the other rules, so this ships off |
| `review_bot` | `off` | `auto`: the conductor also runs the repo's PR review bot on each PR ([`review.md`](review.md)) |
| `sign_commits` | `false` | `true`: every agent signs its commits and merges, and stops if it cannot |
| `keep_panes` | `false` | `true`: `swarm.sh close` leaves a finished agent's pane and tabs open to read; you close them |
| `lessons_file` | `.claude/swarm/brief.md` | where adopted lesson rules live: the brief, `AGENTS.md`, `CLAUDE.md` or `.claude/CLAUDE.md`, the files every agent reads (any other is refused, since a rule there would retire its candidate without reaching anyone). With `AGENTS.md`, rules about writing code reach you and interactive sessions too, and the brief keeps the swarm-only rules. Every brief still gets the file's tagged rule lines (only those), since a builder in another repo's worktree reads that repo's `AGENTS.md`, not this one. The 4 KB cap measures what every prompt carries: the brief plus `lessons_file`'s tagged rule lines; the rest of `AGENTS.md` is not capped |
| `stall_minutes` | `30` | a story's builder that is working this long with no sign of life (no commit in its worktree, no edit there to a file `git status` lists, no update to its PR, no swarm action on its story) is `stalled?`: `wait --stall` returns on it. `dash` shows every working agent's time since its last sign of life after its state (`working 12m`); past this it shows `stalled 40m` instead, marks the agent `!` and lists it under needs you (with `lead = session`, under the lead's queue). An agent with no story (a conductor or planner) has its own `events.tsv` lines as signs: those naming it, and once it has a start line, those its pane ran, nudges and failed tells excepted. Any agent with a Claude session, builder or not, also counts the last write to its session log (`.jsonl`), which the session makes on every turn and tool call. Working is its Claude session reporting busy, for `wait --stall` and `dash` alike, and herdr's working for a codex builder |
| `pr_per` | `story` | `epic`: an epic's stories merge into one branch, and each repo gets one PR for the epic (§ One PR per epic) |
| `sonnet_share` | `0` | `N`: one in N `kind: code` stories without `risk: high` is built on Sonnet (role `code-sonnet`), so `swarm.sh outcomes` can compare it with Opus. The pick is the `cksum` of the slug mod N, so a slug always gets the same model. Only a story's first build is picked: a retry is built on Opus, or on Fable once `escalate_after` applies. `0` is off (§ Model and effort) |
| `escalate_after` | `2` | `N`: a story an agent builds whose `attempts:` has reached N is built on Fable (role `escalate`), whatever its kind, risk or `sonnet_share` pick. An absent `attempts:` is 0, and a value that is not a whole number is refused. `0` is off (§ Model and effort) |
| `builder_subagent_model` | empty | a model such as `haiku`: the agents that build a story start with `CLAUDE_CODE_SUBAGENT_MODEL` set to it and `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`, so their subagents (an Explore search, say) run on it. Planners and conductors are unchanged. Empty leaves Claude Code's choice |
| `goal` | `off` | `N`, such as `goal = 5`: `swarm.sh story` writes each builder a goal condition beside its brief, in `.swarm/briefs/<slug>.goal.md`. It holds the story's **Done when** and **From review** blocks, the reply the brief asks for, a way out (reply `IMPOSSIBLE: <why>` and stop) and `or stop after N more turns`. A condition over 4000 characters, Claude Code's own limit, stops `story` before it makes a branch or worktree. Needs Claude Code 2.1.269 or later. Once the brief is taken up, `story` sends the builder the goal and fails if its session log does not show it set (§ Building, **The goal.**) |
| `codex_minutes` | `10` | `swarm.sh codex-review <base>`, which every brief and the lead use to run codex's review, stops codex after this many minutes: TERM to its whole process tree, a few seconds' grace, then KILL to whatever is left. It then prints `codex skipped: timed out after <N> min` and exits non-zero, and its events.tsv line says the same. It ships on (§ Scoping an epic) |
| `lead` | `off` | `session`: a lead session acts for you, so `dash` splits needs you in two. Needs you keeps only your steps: a story with a **You:** step, an expired login, a draft HLD. Every merge row, an agent waiting on a prompt, a `lead` story with no **You:** step, every escalated story, an empty pane, an agent whose session is gone or unknown, and a stalled agent go in a `lead's queue` box under it, left out when empty. `next` and `status` are unchanged |

The project is `$SWARM_PROJECT` if set, else the nearest directory up from where you are with
`.claude/swarm/config`, else the git repo you are in. A worktree resolves to its main checkout. The
project need not be a git repo: a board kept in a notes vault works, as long as every story names
its `repo:`. When the board is not in the story's repo, the builder leaves the story file alone and
the lead runs `swarm.sh finish <slug>` once the PR merges.

## Model and effort

Every agent's model and effort come from its role, set in one place: `policy()` in
`bin/swarm.sh` (`swarm.sh policy <role>` prints it). Spend on judgment, save on reading:

- **Design is Fable.** The HLD is co-written at `high`, because the user waits on every turn, and
  attacked at `xhigh` before it is agreed. Splitting an HLD into epics shapes all the work below
  it, so it runs on Fable at `xhigh`.
- **Judgment is Opus.** An epic's decomposition into stories runs at `xhigh`. Skeptics and the
  critic run at `high`, because a skeptic is the only gate a story passes before it is built.
- **Reading is Sonnet, running is Haiku.** Surveys read and cite at `high`, since they feed the
  lead, and docs run on Sonnet at `medium`. Verification and chores run on Haiku at `medium`:
  their result is a command's output or a mechanical diff, checked by the conductor.
- **Building code is Opus at `high`**, and at `xhigh` for a story marked `risk: high`. To find out
  whether Sonnet would do as well, `sonnet_share = N` builds one in N of the other code stories on
  Sonnet at `high` (`code-sonnet`). The slug fixes the pick, a retry goes back to Opus, and each
  build's agents.tsv line says which model built it. It ships off (`0`).
- **Codex is the cross-model check**, read-only, because a different model family shares fewer
  blind spots with the one that wrote the plan.
- **Below the design level, Fable is escalation only**: a story that failed twice, or an epic whose
  contradictions no one can reconcile. A story whose `attempts:` has reached `escalate_after` (2 by
  default) is built as `escalate`, on Fable at `xhigh`, ahead of `risk: high` and `sonnet_share`.
  A `kind: lead` story never escalates, since no agent builds it. `swarm.sh close <slug>` counts a
  failed build of a code, docs or chore story (a verify story has no PR to tell a pass from a
  failure, so its close never counts). When the story is still `ready`, its builder is still open (with `keep_panes`, the
  one it retires) and no PR on `story/<slug>` has merged or is open with auto-merge set, it raises
  `attempts:` by one and clears the attempt away: it removes the worktree and `story/<slug>`, here
  and on origin, and closes each open PR unmerged with a comment naming the attempt. The next build
  then starts fresh, and the third runs on Fable. A close after `review`, after a merge or after
  the builder has gone counts nothing, and `reconcile` sending a story back to `ready` never
  counts. If gh cannot list the PRs, the close counts and clears nothing and says why on stderr.
  `swarm.sh close <slug> <cause>` also says why the builder stopped: `met`, `stalled` and `bound`
  count as above, while `impossible`, `paused` and `cleared-on-error` are not attempts and leave
  `attempts:` as it was. `impossible` clears the build away whenever it hands the story on (below).
  `paused` and `cleared-on-error` clear it when the close ends a build under the same conditions,
  or closes the open builder of a `ready` verify story; otherwise they clear nothing and print
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
  any story still `ready` of a kind an agent builds, verify included, and clears its worktree and
  `story/<slug>` here and on origin so a reset builds it again. When the close lists the story's PRs,
  it closes each open one with `gh pr close`. When it lists none (its builder is gone, gh cannot list
  them, or it is a verify story), it runs no `gh pr close`, but deleting `story/<slug>` on origin makes
  GitHub close any PR still open on that branch. The block then says the PRs were not listed, so the
  lead looks before resetting. Any other story, and a name with no story file, is refused before
  anything closes.
- **After Fable, the lead decides.** When the build a counted close ends was `escalate`, the close
  hands the story to the lead: `kind: lead`, `escalated_from:` its kind (`code (default)` when it
  had no `kind:` line), still `ready`, and a block at the end of the file with the attempts' PRs
  (from the same `gh pr list`) and the lead's two choices. It has no **You:** step, because by the
  user's decision of 2026-10-15 the lead decides and then tells the user what it chose and why.
  `next` prints `escalated <slug>` for it, ahead of `gate`. The lead either re-scopes the story and
  runs `swarm.sh reset <slug> <reason>`, which removes `attempts:`, `escalated_from:` and the block,
  or drops it. While the story still says `kind: lead`, reset puts its kind back (no `kind:` line
  for `code (default)`), so the file is its committed text again; a kind the lead set itself stays.
  A builder reads its story in its worktree, so when the board is in the story's repo the re-scope
  merges as a board PR first (and with `pr_per = epic`, the base is merged into `epic/<epic>` too).
  Then the lead runs `reset` and pulls the board in one go: `reset` puts the file back to its
  committed text, so the pull brings in the re-scope, and `story` reads its kind, repo, epic and
  risk from that. `swarm.sh drop <slug> <reason>` takes a dropped story off the board as `finish`
  does (deleted, or `status: done` with `finished = mark`), and the lead commits the change in a
  board PR; it refuses any story that is not escalated. A story is reset at most once: `reset`
  refuses a slug that events.tsv already shows reset, and names when, and a story that escalates
  again after its reset is offered only drop, in its block and in `next`. `reset` also refuses a
  block whose closing marker is gone, rather than remove everything after the opening one. An
  escalated story is the lead's, so it is not listed under waiting on you (`status`, `dash`,
  `gate`). Each step is a line in events.tsv with its UTC time, for the training data:
  `escalate <slug>` when the build starts (`ok (attempt <n>)`), `dialog <slug>` when a conductor
  answers its usage-credits consent (`accepted` or `dismissed`), `escalated <slug>` at the close
  (`ok (attempts <n>, <k> PRs)`), and `reset` or `drop <slug>` with `ok (<reason>)`.
- **Measure before tuning.** `swarm.sh` records every agent it starts (role, model, effort,
  session) in `.swarm/agents.tsv`, and `swarm.sh cost [--since YYYY-MM-DD]` turns that and Claude
  Code's logs into tokens and estimated cost per role. Change `policy()` from that table, not from a guess.
- **The conductor is Opus at `high`, one fresh session per epic**, on the standard context window,
  never 1M. A conductor re-reads its whole context every turn: on the project this came from, one
  long-lived lead session was 80% of all tokens over three days (3.6B of 4.5B, at up to 1M
  context). The board carries the state, so a new conductor costs little.

## Scoping an epic

An epic (`docs/epics/<slug>.md`: goal, **Done when**, out of scope, constraints) becomes stories
with `/plan-epic <slug>`: three surveys (where it lands, what constrains it, what overlaps it), one
lead decomposition into one-PR stories with `kind`, `touches` and `depends_on`, a skeptic per story
(capped at five, the rest logged) and a codex pass, then a critic. Agents write their answers to
`.swarm/<epic>/`. The user sees refuted stories and contradictions first and approves before any
story file is written. About ten agents per run, so scope deliberately.

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
background work. When it starts, an epic still `later` is set `active` (an uncommitted board edit
that `conduct` reports in one line), so `status` and `next` stop listing it as waiting on you. It
runs in a herdr workspace named for the epic's HLD (its `hld:` field; every epic of that HLD shares
it), in a tab named for the epic, in a pane named `conductor`. Each story it starts gets a pane in
that tab, named for the story; a tab holds four panes, and the fifth opens `<epic>-2`. A one-off
story gets a tab of its own. Conductors of different epics can run side by side (each watches only its own epic's PRs, with
`watch --epic`), as long as their stories touch different files; shared files are the lead's alone.

**Pick the wave.** Only `ready` stories whose `touches` do not overlap. Work that edits a shared
file (`AGENTS.md`, root config, schemas, hygiene scripts) is done by the lead, alone.

```bash
swarm.sh story <slug>      # worktree on story/<slug>, a pane, the agent, its brief
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
A codex agent, or one with no recorded session, is waited on through herdr's status. A builder
whose session goes idle while its story is `ready` and has no open or merged PR (a closed one is an
earlier attempt's; for an epic's story with `pr_per = epic`, before `story/<slug>` is pushed) has stopped early, perhaps on a failed request, and nothing else would wake it. `wait` tells it
why ("you are idle and story/<slug> has no PR") and waits again, up to three times. Nudges are at
least a slice apart unless the session turns busy in between. If herdr cannot deliver a nudge,
`wait` stops there and returns idle, and logs nothing for it. With `goal` on, `wait` nudges no builder, whatever its session log shows: a nudge would bury the reply and the goal entry the conductor reads the cause from, so `wait` returns idle and the conductor reads why it stopped. Only code, docs and chore stories are
nudged, never a verify story, a conductor or a planner, and a gh or git call that fails counts as a
PR. An idle agent whose transcript (its session's `.jsonl`, the file `cost` reads) ends on Claude
Code's "Login expired · Please run /login", with no message sent to it since, is never nudged or
waited on: `wait` prints `auth` at once,
with a line on stderr naming it, for a builder and a conductor alike. Only the user's `/login` clears
it. Once they have run it, tell the agent to resume (`swarm.sh tell`), and a conductor tells the same
to each builder whose `wait` printed `auth`. `wait` does not read the pane. `wait --stall
<slug>` also returns, with exit code 3 and `stalled: working <N> min with no commit, edit, session-log write or PR update`, when the
builder (busy, as above) has shown no sign of life (a worktree commit, an uncommitted edit in the
worktree, a write to its session log, a PR update, a swarm action on its story) for `stall_minutes` since that wait began. `watch` is what the lead waits on: it
exits when a story PR's checks finish, when it conflicts with its base, when its head has had no checks
for 10 minutes, or when an agent's session is waiting, and it names what the agent waits for. A codex
agent, or one with no session recorded, counts as waiting when herdr says it is blocked. Each agent's
wait is reported once, and again only after a poll finds that agent no longer waiting; a poll that
cannot read the agents changes nothing. herdr lists every project's agents, so
`watch`, and `next` when it looks for a running conductor, count only agents in panes this project
opened (recorded in `.swarm/state`); an agent started by hand is not watched.

**The goal.** With `goal = N`, once the builder has taken up its brief, `story` sends it `/goal`
followed by the condition in `.swarm/briefs/<slug>.goal.md`, joined onto one line, once, through
`herdr agent prompt`. The builder is mid-turn by then; Claude Code still sets the goal straight
away, and runs one extra short turn after the brief's turn ends. From then on Claude Code's judge
keeps the builder working until the story's **Done when** holds, the builder replies
`IMPOSSIBLE: <why>`, or N more turns have passed. The judge records all three as met, and only its
reason text tells them apart. `story` looks for the goal in the builder's session log and does not
read the pane: it waits up to a minute for a `goal_status` entry with that condition (whitespace
aside), written after the send. If Claude Code refused
the goal (hooks restricted by settings or policy, or a folder it does not trust), or no entry came,
`story` fails, names the story and the reason, and leaves the builder open for the lead to look at.
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
when it is idle with no PR (with `pr_per = epic`, no pushed `story/<slug>`) after wait's nudges, or
when review has not converged in the rounds it allows. It runs `swarm.sh close <slug>`, which, on a
code, docs or chore story still `ready`, counts the attempt and clears its worktree, branch and PR,
and starts the story again in a later wave with
`swarm.sh story <slug>`; swarm.sh picks the model, Fable once the story has failed `escalate_after`
builds (2 by default). With `escalate_after = 0` it reports a story that has failed twice to the lead
instead. A story that comes back `kind: lead` with `escalated_from:` is the lead's to decide, never
the user's. With `goal` on, a builder idle short of its reply is not nudged: the conductor reads the
cause from its reply and the last met `goal_status` entry's `reason` in its session log, closes it with
`swarm.sh close <slug> <cause>` (`stalled` for a stall), and on `cleared-on-error` starts nothing more
in the wave and lists the story for the lead. A Fable builder can stop on its usage-credits consent, which `wait` prints as
`waiting: dialog open`. Only for an escalate build, and only once `herdr agent read` shows that
consent, the conductor accepts it with `herdr pane send-keys` in the builder's pane, runs
`swarm.sh dialog <slug> accepted` (or `dismissed`, telling the lead), which logs `dialog <slug>`
with its time, and waits on the builder again. It never closes or tells a builder over a dialog, and
a dialog is not an attempt. Any other dialog, and every permission or tool prompt, it leaves alone.
`/swarm-dev:swarm` does the same for the lead's one-off stories.

**Watching it.** `swarm.sh status` lists the agents that need a look (waiting on a prompt, an
empty pane where a start failed, a session gone or unknown, or `auth`: an idle agent whose
login expired, which only your `/login` clears), what waits on you, and the next step. `next` says
`auth` too when the conductor's login expired. A Claude agent's state comes from its own session in `claude agents --json`, read once per
run: busy is working, idle is idle, waiting is WAITING with what it waits for, and a recorded
session with no entry in the list (`gone`: the session ended) or no state in it (`unknown`, also
when there is no `claude` to ask) needs a look. herdr's word stands only for codex agents, agents
with no session recorded, and retired panes. `swarm.sh dash` shows the
same on one screen, for a person to scan: a summary line, then what needs the user first (PRs to
merge with their checks, `lead` stories, agents waiting on a prompt (with what their session waits for), agents whose session is gone or unknown, agents whose login expired, empty panes, stalled agents,
draft HLDs), each active epic with a bar of its finished stories (finished story files are deleted,
so they are counted from history: a deletion counts once per slug, and only when it closed the story,
never a re-scope) and its live agents and open PRs beneath it,
and the recent events with how long ago; idle agents and blocked or later items are counts. One
status vocabulary runs through it (● working, ○ ready, ◐ review, ✓ done, ✗ failing, ⏸ blocked, ! needs you or a
session gone or unknown, ? a herdr state dash does not know).
`--tree` shows the agents by workspace and tab and `--ladder` the model per role; `dash --watch
[seconds]` redraws it in place until `q`, with `t` and `l` toggling the two. Both only read: they never change the board, the state or the logs, and never open
or close a pane, so `dash` asks herdr for the agents even outside a herdr pane.

**The audit log.** Every `swarm.sh` command appends one line to `.swarm/events.tsv`: the time,
the command, its target, the herdr pane that ran it, and how it ended: `ok`, `interrupted`, the first
line of the error that stopped it, or `failed (exit N)` when the error came from a nested step, whose
message a caller may have handled (it still reaches the terminal). Only the read-only commands are
exempt (`READ_ONLY_COMMANDS` in `bin/swarm.sh`: `dash`, `status`, `next`, `config`, `policy`,
`cost`, `outcomes`, `decisions`, `lessons`, `findings`, the `wait` and `watch` that conductors run all the time, `base`, and
`tidy` without `--yes`), so a new command is logged until someone names it read-only. The one
exception is `wait`, which logs each nudge it sends as `nudge <agent>`. The stall rule skips those
lines, because a nudge is not a sign of life. A `tell` is logged as `tell:<kind>` with the slug as
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
or `error <why>`, then reconcile's lines. A `story` that starts an `escalate` build, and the `close` that hands its story to
the lead, each write one more line of their own (§ Model and effort). The log is local to the machine and append-only,
holds names and paths but never a brief's or a message's contents, and a write that fails never
fails the command.

`swarm.sh outcomes [--since YYYY-MM-DD]` joins the logs per build. It prints one TSV row for each
builder in `.swarm/agents.tsv` with the story's slug, kind and risk, the model and effort, the cost
and tokens from the session's own log, the tells it took by kind (`tells_findings`, `tells_nudge`, `tells_resume`; a bare `tell` from older logs counts as findings, and a refused tell, which never reached it, is not counted) and its `close` lines in this log (any cause), the findings logged
against its PR, the PR and its state from `gh`, and which attempt at the story it was. Then come
`started` (the first timestamp in the session log, in UTC, or empty with no log), the tokens by type
(`tokens_input`, `tokens_cache_write`, `tokens_cache_read` and `tokens_output`, which add up to
`tokens`), `close_cause` (the cause on the build's last close, empty for a plain `close`), and when
each escalation step was logged: `escalate_at`, `dialog_at` with `dialog` (`accepted` or `dismissed`,
otherwise empty), `escalated_at`, `reset_at` and `drop_at`. The reason given to a reset or drop is
never printed. New columns go on the end, so `decisions`, which reads them by name, keeps working. The slug comes
from the session's worktree, because agents.tsv cuts names at 32 characters. Each build gets its own
PR: the last of the story's PRs that its session log names, so a retried story shows the first build's
closed PR beside the retry's merged one. A build whose log names none of them has no PR, and a build
with no log left gets the story's PR only when it has exactly one. With `pr_per = epic`, builders open
no PR, so every build of an epic story gets the epic's PR. A story that merged and
left the board is read from git history. If `gh` fails, the PR columns stay empty. It writes nothing.

Each `events.tsv` line counts for one build, so a retried story's tells and closes are split among
its builds. A line whose time does not parse counts for none. An escalation step goes by the order of the log. Each `escalate` opens a cycle for the
story's next escalate build in agents.tsv that has none yet. A later escalate build takes the cycle
instead when its session log started nearer this `escalate` than any other of the story's, and nearer
than that first build. So a build whose brief was never taken up (it logged no `escalate`) cannot take
its retry's cycle, and a build whose log is gone keeps its own. The cycle runs until the
story's next `reset`, `drop` or `escalate`, and every step logged in between belongs to that build.
If a step repeats in one cycle, the last one counts. A tell or close goes to the story's build that started last at or before it. A build whose
session log is gone starts at 00:00 local time on its agents.tsv day, converted to UTC.

`swarm.sh decisions [--since YYYY-MM-DD]` exports the same logs as training data for a small
decision model. It prints one JSON object per line for each decision the logs record: a
`model_choice` per agent started, a `retry` per later attempt at a story, a `finding_accept` per
finding fixed or declined, a `nudge` per `nudge` or `tell:nudge` line, and a `close` per `close` or
`close:<cause>` line, with the command as its `chosen`.
Each object has `decision`, `time`, `subject`, `context` (a builder's story as committed to the board
by the end of the day it started, or the finding's text), `options`, `chosen`, and `outcome`, which is
that build's `outcomes` row: merged, PR, `tells_findings` (its review rounds), `tells_nudge`,
`tells_resume`, fixed findings, attempts and cost. A field the logs
don't hold is null. It writes nothing.

`swarm.sh close` keeps the Claude session log of each agent it closes (every agent in a tab it closes), because Claude Code deletes those after
`cleanupPeriodDays` (30 by default) and they hold every tool call and the model of every turn. The log
is copied, gzip'd, to `.swarm/sessions/<date>-<agent>-<session>.jsonl.gz`, once per session; a codex
agent has none to keep. Nothing is redacted, because a list of what to scrub misses whatever it
doesn't list, so the copy holds whatever the session held. The copy is readable by its owner only,
and `.swarm/` is git-ignored: the archive stays on the machine, and is never committed or uploaded.
`cost`, `outcomes` and `decisions` read a session's live log while it exists and this copy once
Claude Code has deleted it, matching the copy on its session id, so their tokens, cost and slugs
outlast the 30 days. The stall rule, the goal check and `dash` never read the copy: an archive is
no sign that an agent is alive.

The builder's brief is the story file plus the standing rules (never merge, no real cloud, the
codex loop through `swarm.sh codex-review <base>`, reply with the PR URL when CI is green), the epic's `check:` command when it has one
(the builder runs it before opening the PR), then the project's own rules from
`.claude/swarm/brief.md`. When those rules include tagged ones (`<!-- lesson: <kind> -->`), the
brief adds a last step: before opening the PR, the builder walks its diff against each one and gives
the PR body (its reply, with `pr_per = epic`) a `Rules checked:` section, one line per kind naming
what it checked (file:line) or `n/a: <why>`. With no tagged rule there is no step. `herdr agent read <slug> --source recent-unwrapped` shows what an agent
is doing.

**Review before closing.** A PR that changes only board files (no code) gets one
`swarm.sh codex-review` pass plus the lead's own reading, not repeated passes. A story is reviewed when its latest head has passed
codex and, if it changes code, the `/code-review` skill. The conductor sends the findings to the story's builder with
`swarm.sh tell <slug> findings <file>` and reviews the new head again. The kind (`findings`, `nudge`
or `resume`) is required and goes in the audit log. `tell` sends only to an idle session. It
refuses a builder that is still working, waiting on a prompt (it names what the prompt is), or whose
session is gone or unknown. To reach a busy conductor, the lead runs
`swarm.sh tell conduct-<epic> note <file>`. It appends the file under a timestamped header to
`.swarm/inbox/conduct-<epic>.md`, without sending a prompt or reading the conductor's state, and
only for a live conductor of this project. After each `wait` or `watch` returns, the conductor moves the
inbox with `mv` to `conduct-<epic>.reading.md` beside it (so a note added meanwhile starts a new
file), reads that copy, acts on it and deletes it. A copy already there is a read that was cut off,
so the conductor reads and deletes it first. It does all of this once more just before it writes its
report, so a note left after its last wait is still read. Once a new conductor has started,
`conduct` clears both files, so it never acts on notes left for the one before. A `conduct` refused
because the epic's conductor is still running leaves them alone. The conductor closes a builder only after both
reviews pass, so the fixes are made by the agent that wrote the code, with its context. A pass
that finds only nits, edge cases outside the story, or points already declined counts as passing: a
reviewer built to find edge cases never comes back empty, so waiting for an empty pass never ends. With
`pr_per = epic`, stories have no PR: each epic PR gets `/code-review`, fixed on the epic branch. Each builder
also proves its tests can fail: it breaks its fix, watches a test fail, and restores the fix.

Every codex review a builder, a conductor or the lead runs goes through `swarm.sh codex-review
<base>`, in the worktree, with `SWARM_PROJECT` set to the project so a worktree of another repo still
reads its config. It runs `codex exec review --base origin/<base>` with no prompt (codex refuses one
beside `--base`) and stdin from `/dev/null`, and stops it after `codex_minutes`. An interrupted
codex-review stops codex the same way and exits only once it is gone. While it runs it keeps a marker,
`.swarm/state/codex-review.<pid>` (start time, base, worktree), which the dash reads for its codex
row. It removes its marker when it exits, and on start removes any marker whose process has died. codex stays in the caller's
process group, so a harness that kills that group kills codex too. Every brief says to run it in the
background (Bash `run_in_background`) and wait for it: Claude Code stops a foreground Bash call at 2
minutes by default and 10 at most, before the limit could apply. When codex reports a
usage limit, or codex-review prints `codex skipped: timed out`, no one waits or runs it again: a
builder carries on, the conductor or the lead reviews the diff itself, and the PR says `codex
skipped: usage limit` or `codex skipped: timed out`. The planning `codex` panes of `/plan-hld` and
`/plan-epic` are not run this way: `wait`'s timeout bounds them, and the lead closes them.

**Learning across epics (the outer loop).** Each finding that review fixed is logged with
`swarm.sh log-finding --reviewer <who> <kind> <PR> "<one line>"`, where the kind names the class of mistake
(`vacuous-test`, `denylist`) and `<who>` is the reviewer that raised it: `codex`, `code-review`, `ci` (a
PR review bot, a check-run note or a code-scanning alert), `conductor` or `lead`. Each finding declined is logged with `log-finding --declined`, with the
reason in its line; `lessons` and `outcomes` count only the fixed ones, and `decisions` exports both. `swarm.sh lessons` counts kinds across PRs: a kind fixed in three or
more PRs that the project's `lessons_file` (default `.claude/swarm/brief.md`) has no rule for is a `candidate`. So is a lead
memory (Claude Code's per-project memory, which builders in their own worktrees never see) whose
frontmatter carries `lesson: <kind>`: tag a memory that is about how code is written, and it reaches
the builders the same way. Every builder and conductor gets that file's rules (the brief is pasted
into their prompts whole; from another `lessons_file`, its tagged rule lines are), so one rule
there reaches every later builder and conductor, in any repo. A rule pasted into a prompt does not
stop the mistake by itself, so each builder checks its diff against every tagged rule and lists what
it checked under `Rules checked:`; the conductor logs a missing section, a missing kind, or a line
that names nothing as a finding of kind `rules-unchecked`. `/swarm-dev:swarm` turns candidates into a short rule, tagged `<!-- lesson: <kind> -->`, and
opens it as a PR titled `lesson: <kind>` for you; it never edits the brief silently, and a kind
whose rule PR you closed is not proposed again. Only PRs from the last 90 days count. With `pr_per = epic` a finding is logged against the epic
PR of its repo, so findings count per epic per repo. A brief over 4 KB (counting `lessons_file`'s tagged lines, which every brief also carries) is flagged, and pruning it is your call: a rule that works stops
its own findings, so quiet is no sign a rule is unneeded. The log is `.swarm/findings.tsv`, local to
the machine: date, kind, PR, the line, its outcome (`fixed` or `declined`; rows written before the
outcome column count as fixed) and the reviewer (`unknown` when a row was logged without `--reviewer`
or before that column existed). Columns added later go on the end, so readers ignore any past the sixth.

**Green means more than green checks.** A check can pass and still carry a failure note (a
code scanner often does), so the lead also triages `swarm.sh findings <repo> <pr>`: the notes on
every check run of the PR's head, and its open code-scanning alerts (the first 100 of each). Each is fixed, or rebutted in
the PR with a reason; none is silenced or dismissed.

**Merging.** With `merge = human` (the default) no agent merges: each agent starts unable to run
`gh pr merge`, and its brief forbids every other route. When a PR is green and reviewed, the lead
runs `swarm.sh review <slug> <PR URL>...`, which sets the item `status: review` with its PRs on a
`prs:` line, and `next` lists it as awaiting your merge. When the stories left in an epic are all
in review and its **Done when** will hold once they merge, the conductor puts the epic in review
too, with every PR still waiting. You merge on GitHub; the next `/swarm-dev:swarm` runs `swarm.sh reconcile`,
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
Before it pulls the board's repo, it sets the front matter that swarm.sh wrote on each merged item
back to what is committed (the `review` status, and a retry's `attempts:`), and puts the whole file back as it was
if the pull fails. It also puts back any board file the main checkout
left unstaged with content already the base's, so a hand edit that matches what merged does not
stop it. When the pull changes a board file whose only unstaged edit is to keys swarm.sh writes
(`status`, `prs`, `blocked_by`, `attempts`, `kind`, `escalated_from`), such as an `unblock` flip or
another story in review, reconcile checks the file out, pulls, then sets those keys again. If the
pull deleted the file, it stays deleted; reconcile prints its name and keeps the backup, which holds
the edit. If the base changed one of those keys as well, to a different value, reconcile stops
before it touches anything and names the file. It also stops when the edit changes `status` and the
base changed `blocked_by` or `depends_on`, so a flip to `ready` never lands over a new dependency.
Every file it puts back or checks out goes into `.swarm/state/reconcile-backup/` first, and
reconcile prints where. If the pull still fails they are all restored, and if a key cannot be set
again after it, the backup stays. It touches nothing, and stops naming why, when the pull cannot fast-forward or
a file outside the board is changed; a staged edit, or an edit to anything else in the file, is left alone and still stops it. `swarm.sh unblock` then readies a
blocked story once every slug in both its `blocked_by` and its `depends_on` is finished. With `merge = agent` the conductor merges instead.
It waits out a queued merge (auto-merge, a merge queue), then runs `swarm.sh review <slug> <PR URL>`
and `swarm.sh reconcile`, which pull the board the way they do for you, putting back a retry's
`attempts:` first, and finish the story, closing its builder. The conductor never closes the builder
before that, because closing a story that is still `ready` counts a failed build. The lead merges
with `swarm.sh merge`: a one-off story with `merge = agent`, and any PR you ask it to merge, under
`merge = human` too.

`swarm.sh merge [--board] [--head <sha>] <PR URL>` merges one PR. It refuses, merging nothing,
unless the PR is open, its head is `<sha>` when `--head` names one, and a story or epic in `review`
lists the URL on its `prs:` line. With `--board`, for a board-only PR, the PR must be in the
board's own repo (its origin) and every path it changes, a renamed file's old path too, must be
under the board instead. The head must be green: at least one check run, every run
completed as success, skipped or neutral, and every commit status a success. It reads every page,
and any gh error or answer it cannot read is a refusal. It merges with the repo's method (squash
when allowed, else a merge commit, else rebase) and `--match-head-commit`, so a head that moved
after the check stops the merge. It never passes `--auto`, and passes `--admin` only with
`merge_admin = true`, after checking that every status check the base's rulesets or branch
protection require passed on the head, from the app it names when it names one. `--admin` also
bypasses required reviews and every other rule on the base, which nothing checks.

It reads the PR back after `gh pr merge`, whether gh succeeded or not, since an error can follow a
merge GitHub made. A PR that does not read as merged is read again a few times, then logged as
unconfirmed, for you to check by hand: it may well have merged. Only a failed `gh pr merge` on a PR
that still reads open or closed is a refusal. Then it waits up to 30 minutes for CI on the merge
commit, so run it in the background: each workflow whose `on: push` filters cover the base and the
files the PR changes must have a run on that commit, and every run and check there must pass. The
commit needs no check run of its own when no workflow is expected on it, but then it waits a minute
before calling main green, for checks other apps post just after the push. A failed read is a
missed poll, and three in a row end the wait as an error. Without
`--board` it then runs `swarm.sh reconcile`, also after a red main, since the PR has merged. It
exits non-zero, naming the check, when main is red or the wait runs out. Inside herdr it runs only
from a pane this project did not start (the lead's), or from a conductor's with `merge = agent`; a
pane it cannot identify is refused.

**Merge one at a time.** After each merge, merge the base branch into every other open wave branch before
trusting its CI; a branch that conflicts gets no CI at all, which looks like a hang.

**One PR per epic.** With `pr_per = epic`, the first story of an epic built in a repo creates
`epic/<epic>` there from the repo's base branch, and adds the repo to the epic's `repos:` line.
Each story branches from `epic/<epic>`, and its builder pushes `story/<slug>` and opens no PR. The
conductor reviews each branch, merges it into `epic/<epic>` with `git merge --no-ff`, runs the tests
and the epic's `check:`, and finishes the story. When the last story is in, it runs `swarm.sh
codex-review <base>` over the whole epic (`swarm.sh base <repo>` prints the base) and opens one PR per repo, written
for a reader who knows nothing of the stories. Those PRs then go through the same green and merge
rules as any other. If a conductor stops before the PRs, `next` sees an active epic with a
`repos:` line and no open story, and starts a fresh one, which picks up there. Stories outside any
epic keep their own PR.

**Keep with the lead:** real-cloud runs, credentials, and anything that changes permissions.

**Clean up.** After each merge, `swarm.sh reconcile` closes the story's builder if it is open and
removes its worktree and `story/<slug>`, here and on origin (§ Merging). By hand,
`swarm.sh close <slug>` closes a story's pane (its tab, when it was the last pane there), and
`swarm.sh close conduct-<epic>` closes the epic's tabs.

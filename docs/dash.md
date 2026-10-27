# Watching the swarm

`swarm.sh dash` prints one screen of what the swarm is doing; `swarm.sh dash --watch [seconds]`
keeps it open and redraws it in place every 2 seconds (or the seconds you give), repainting only
when something changed. Press `q` to quit (Ctrl-C works too), `r` to redraw, `t` to switch to the
agents by herdr workspace and tab and back, and `l` to show the model per role; resizing the
terminal redraws it at the new size. It works in any terminal, inside herdr or not: it only reads,
so it asks herdr for the agents whenever `herdr` is on your PATH. It never changes the board, the
state or the logs, and never opens or closes a pane. In a folder with no board it stops with one line
naming `swarm.sh init`.

Each frame gives its reads of herdr, Claude Code's session list and GitHub 30 seconds in all
(`SWARM_REPORT_SECONDS` sets a different number of seconds). A read still running at that point is
stopped, and a read that comes later is skipped. dash draws the frame from what the other reads
gave, then names the stopped and skipped reads on its last line: `skipped (over 30 s): gh PR states,
herdr agent list`. So `--watch` draws its first frame within about 30 seconds, even when herdr or
GitHub hangs. When the PR states are cut short, dash keeps the ones it got for the next minute, and
the rest show as their URLs. The 30 seconds run from the frame's start, so on a busy machine dash's
own work between the reads takes part of them; its read of each agent's pane for a usage-limit
dialog (10 seconds at most each) is never cut, and comes on top. With `--project` the projects share
one 30 seconds. `dash --check` reads everything in full, like the commands it compares with.

To watch more than one project, name each with `--project <dir>`: `swarm.sh dash --project
~/src/app --project ~/src/infra` draws app's screen and then infra's, each headed by its project's
name, with the legend once at the bottom. `--watch` on a terminal redraws them together as one
screen, each with its share of the height left above the legend. Anywhere else nothing is cut, as
with plain `dash`. If one project's screen fails to draw, its error takes its place and the others
still show. It checks every folder before it draws anything, and stops at the first one that has
no `.claude/swarm/config` or no board, naming it. With `--project` it shows only the projects you
name, so you can run it from any folder, even one outside every project and git repo.

When `claude plugin update` installs a new version while `--watch` runs from the installed plugin,
the watch switches to the new version's `swarm.sh` before its next frame and keeps your `t` and `l`
choices. It reads the version from Claude Code's `installed_plugins.json`. Run from a checkout of
this repo, it never switches.

In a terminal at least 140 columns wide it splits into two columns: needs you and the epics on
the left, recent as a timestamped log on the right, and a status bar on the last line. Narrower, it
is one column, top to bottom:

- **Header**: the project, the swarm-dev version, the `merge` mode, what `/swarm-dev:swarm` does next, and the
  time of the last refresh. Under it, at every width, the speedometer: `2.0 merged/day over 7 days`
  is the number of stories the swarm finished on the last 7 calendar days, today included, divided
  by 7. dash reads them from `events.tsv`: a `finish` line, or `reconcile`'s `finished` line once a
  story's PR merged, each slug counted once, on the day it last finished. A story that was dropped or rescoped writes neither, so it never counts. It asks gh
  nothing. Two lights follow it,
  each `!` and lit when its count is above 0, `✓ 0` when not. The first counts what waits on you
  (or on you or the lead, with `lead = session`): every row in needs you and the lead's queue, plus
  the stories behind `+N more`. It also says how long the oldest one has waited: a board item waits
  from its newest `review`, `kept`, `close:<cause>` or `escalated` line in `events.tsv`, or else from its
  file's last commit. A `no agent on story` row waits from the event that explains it. The second counts the escaped defects logged in the last 7 days
  (`--reviewer escaped` in `findings.tsv`). A third light shows only when someone had to step in on
  those 7 days: `! N interventions in 7 days`, the `swarm.sh intervene` lines (`lead-hand` and
  `user-caught`), the same count `flow`'s `incidents` section gives for them. It goes on the
  speedometer's line when it fits, and on the next line when it does not; a frame cut to the
  terminal's height drops that line after the sparkline, the gauges and the `idle:` count. From 60 columns a sparkline follows: the stories
  finished on each of the last 14 days, oldest first (`▁` for none, `▇` for the busiest day), then
  today's count and the average of its last 7 days, which is the speedometer's number. From 100
  columns two gauges follow, on the sparkline's line when both fit. `rate` is that average against the best 7 days in a row
  in `events.tsv`. `running` is the agents working now, exactly the ones `swarm.sh status` lists as working (the
  summary's count; codex reviews are not among them), against the most agents that were busy at once
  on the same 7 days. dash works that peak out from each
  `agents.tsv` session's log, taking the first timestamp as the start and the last write as the end,
  so a session that sat idle for a while counts as busy; one that ends as another starts, in the same
  second, is no overlap. Each kind of agent has a cell and a colour
  of its own: `█` builders (green), `▓` conductors (cyan), `▒` review agents (yellow), `▪` anything
  else. After it, `idle: <n> buildable not started` counts the stories `swarm.sh next` would start (ready, of a kind an agent
  builds, a one-off or in an active epic, a one-off with no worktree yet) that have no builder, no conductor of their
  epic and, for a one-off, no backlog conductor in this project's panes; it is left out at 0.
  With no agent list from herdr the running gauge and the idle count are left out. When a watched frame is too short to
  keep the ladder, a few rows of recent and (from 140 columns) the whole left column, the sparkline's
  line goes first, then the gauges. Then one summary line: epics active, agents working (as
  `swarm.sh status` counts them, stalled ones included), PRs green and waiting for you, stalled builders, and today's
  estimated cost of this project (the `cost` section of `swarm.sh flow --since <today>`, without the session of the
  pane dash runs in). After
  it comes who is on call (`on call: fable·xhigh`, the escalate role's model and effort, or `on
  call: off` with `escalate_after = 0`) and how many builds escalated to it today (`0 escalations
  today` too), on the same line when they fit there and on the next line when they don't. Then CI
  time against last week, for the project's origin repo: `ci 11m (slowest: test 9m) ▼2m vs last
  week`. It is that repo's row of the ci time table in the `ci_health` section of `swarm.sh flow
  --since <6 days ago>`, which dash runs in the background at most every 6 hours (10 minutes after
  one that failed or could not read one of this week's PRs, which keeps the line there was, and one
  at a time, stopped after 30 minutes), so the line appears a minute or so after the first dash. A line older than 6 hours says so: `· 9h old`. Then a
  warning when the main checkout has board edits not committed yet, naming the files, cut to the
  width: `board: 2 uncommitted edits in the main checkout: stories/a.md, stories/b.md`. From 140
  columns the merge mode, the summary, who is on call and the ci line move to the status bar.
- **Needs you**: only what you act on, one short action a line: `merge` a PR (with its checks and
  whether it is behind the base), `run` a `lead` story (with its title), `answer` an agent waiting
  on a prompt (with what its session waits for), `auth: run /login` for an agent whose login expired (it is idle, but only your `/login` clears it), `close` an empty pane, `look at` an agent whose session is gone or unknown, `look at` a stalled agent (working for `stall_minutes`, 30
  by default, with no sign of life: for any agent with a Claude session no write to its session log, for a builder also no commit or uncommitted edit in its worktree, PR update or swarm action on its story,
  for an agent with no story (a conductor or planner) no `events.tsv` line naming it or run from its
  pane, nudges, resumes, incidents and failed tells excepted), `agree` a draft epic, `staged epic
  <slug>: stage v<T>, after v<P>` for a staged draft epic, which the lead sets active once the base
  has a tag at or above `v<P>` and which gets no `agree draft epic` row, and `no agent on story` for
  a started story that no agent works on any more. That last row is the `no-agent:`
  line `swarm.sh wait --lead` wakes the lead with. It names the story and what to run:
  `swarm.sh hold <slug> <reason>` for a ready story, and for one in review `swarm.sh merge` once a
  review passed on its head, else `swarm.sh review-agent`. A story whose exit is a merge and that
  already has a `merge` row gets no second row. The row shows only once an event explains why
  the agent is gone: an ok close, a failed start, or the `no-agent` line a `wait --lead` poll
  writes. A pane that closed with nothing logged gets no row until a `wait --lead` poll has run
  since, and with `lead` off nothing may run one, so the row may never show. To draw it, dash reads
  herdr's agent list once a frame and writes no `events.tsv` line. A `lead` story's row ends with
  who it waits for: `waits for: you: create the read-only user`, with the text of its first
  **You:** line, or `waits for: the lead` when it has none. Only your next **You:** step is listed,
  the first ready `lead` story that has one, with `+N more` when other stories have one too. When
  nothing needs you, it is one line. A story a close kept (its PR not reviewed) is a
  `review kept story <slug>` row with its two ways out: `swarm.sh review <slug> <PR URL>` once you
  have reviewed it, or `swarm.sh close <slug> --drop`, which closes the PR and sends the story back
  to ready.
- **Lead's queue**, only with `lead = session` in the config: a lead session acts for you, so needs
  you keeps only your steps (`run` a story with a **You:** step, `auth`, `agree` a draft epic) and
  everything else from the list above moves to this box under it: every `merge`, `answer`, `close`,
  `look at`, `staged epic` and `no agent on story` row, a `lead` story with no **You:** step (`waits for: the lead`), and `decide` for
  every escalated `lead` story (`swarm.sh reset` or `swarm.sh drop`), and `review kept story` for
  every story a close kept (`swarm.sh review` or `swarm.sh close <slug> --drop`). It is left out when
  empty.
- **Idle capacity**: the `idle:` lines `swarm.sh next` and `wait --lead` print for blocked stories, one
  row each: `idle: <story> waits on <dep> but shares no touches part with it and needs nothing from it`.
  dash works them out again every frame from the board and its state, with no gh call, so a row goes
  once the dependency is in review or done. They count toward no warning light. The box is left out
  when there are none, and, with no warning, when the check fails: a frame has no place for one.
- **Running now**: one row per agent open in this project's panes (empty panes and retired agents
  aside). Each row has the agent's name, how long it has run (`up 25m`, from its `story`, `conduct`
  or `agent` line in `events.tsv`, or else from midnight on its `agents.tsv` day) and its last
  activity: the newest tool in its session log and how old the log's newest entry is (`Bash 3m
  ago`). A builder's row also has its open PRs and their CI state (`#11 green`), or `no PR yet`.
  Its PRs are the ones its story lists. While none of those is open (the story lists none until
  review, or only a closed PR from an earlier attempt), the open PR on its `story/<slug>` branch
  counts instead; dash asks gh for those once a minute per repo. Held stories
  (`held_for:` set) come after the agents, each with its cause (`held rh-held: paused`). The box
  is left out when no agent is open and no story is held. Narrower than 140 columns it sits above
  recent (under the ladder, when that shows), so recent gives up the lines it takes; from 140
  columns it sits in the left column under the epics.
- **Epics**: one row per active epic, with a bar of its finished stories out of all of them and how
  many open stories are in each status. An agent's status is its Claude session's (`claude agents
  --json`, read once a frame): busy is working, idle is idle, waiting shows what it waits for, and a
  recorded session that is `gone` (it ended) or `unknown` (no state, or no `claude` to ask) is
  marked `!`. So is an idle one whose transcript ends on an expired login: it shows `auth`, since
  only your `/login` clears it. herdr's word stands for codex agents, agents with no session recorded, and retired
  ones. An idle conductor whose report is written shows `reported`. Its epic comes from its name.
  When herdr cut that name to 32 characters, it comes from the one conductor the records hold under
  the cut: an epic on the board, an ok `conduct` line or a brief, so it holds once the epic's file
  has left the board. With none, or two, or a story under the cut too, it is not `reported`. Nor is
  an agent that `agents.tsv` records in another role, though it holds a conductor's name. A finished story's file is deleted, so finished ones are
  counted from the board repo's history: story files deleted on its base branch (and on HEAD) whose
  front matter named the epic, once per slug, when any deletion closed the story: its own PR's
  merge (the commit names `story/<slug>`), its own work (a squash merge: the commit also changes a
  file that is neither the board's own, its `stories/`, `epics/`, `hld/`, `.obsidian/`, `Board.base`
  and `README.md`, nor a root `*.md`, and names no `board/`, `close/` or `epic/` branch),
  the swarm's logged `finish`, or a last status of `done` or `review` or a `prs:` line. A story
  still on the board here is open, and a re-scope counts as nothing. The row's symbol is ○
  when stories are ready and nothing runs, and ⏸ only when every remaining story is blocked or later. Under it, its live agents (role, model and effort, status) and its open PRs. A working
  agent's status carries how long since its last sign of life (`working 12m`), and past
  `stall_minutes` it reads `stalled 40m`, marked `!`. Every agent's row ends with how long since
  its pane last changed (`pane 12m`), as `status` or `wait` last saw it. An agent neither of them
  has read within `stall_minutes` shows none. From
  140 columns each agent is a card: the model and effort sit on a label in the model's colour, and
  a working agent also shows how long ago it started (its `story`, `conduct` or `agent` line in
  `events.tsv`). An escalate agent also shows which attempt its Fable build is and when it
  started, from its newest `escalate` line (`attempt 3 · 14:02`). A codex review running through
  `swarm.sh codex-review` is a row too, `codex review <worktree> vs <base>` with how long it has
  run, under the epic of its worktree's story (or of an `epic-<epic>` worktree). It never goes in
  needs you or the lead's queue, and it drops off once its process is gone or it has run past
  `codex_minutes` plus a minute. Idle and
  retired agents not on an open story are one `+N idle` line; agents on no epic come last. An idle
  one-off builder there (its story is on no epic) shows what it waits on instead of `idle`, with
  its open PR first when it has one: `#12 IMPOSSIBLE` when its last reply starts `IMPOSSIBLE:`,
  `#12 waits for the lead's merge` once its story is `status: review`, `#12 waits for review`
  while its PR is open and its story is not in review, and `no PR yet` otherwise. `--tree` shows
  the same words for it. Active
  epics with no open story share one line. An epic with no stories whose `depends_on` still holds up its
  planning (as `swarm.sh next` decides) keeps its own row instead, which reads `waits on <depends_on>`. Blocked and later items are one count line under it;
  `swarm.sh status --all` lists them. `--tree` (or `t` while watching) shows every agent by herdr
  workspace and tab instead.
- **Recent**: newest first, with how long ago (`4m ago`, `2h ago`; a dated finding in calendar
  days, `today`, `yesterday`, `3d ago`): merges on the base branch (⇡), review findings
  fixed (✎, one row per PR and day, so a fix's `log-finding` line is not shown again), declined
  findings (a run of them on one PR is one row, `8 findings declined on #133`), agents, conductors and builders started (▶), escalation
  steps (▲: `escalate`, `dialog`, `escalated`, `reset` and `drop`), and the swarm's other actions
  (·); a failed one is ✗. A run of lines with the same action, target and outcome is one row
  with a count, `tell:nudge s-one ×3`. A findings row too long for its column is cut in its text,
  so it still ends with its `(#PR)`. It fills the rest of the screen. From 140 columns it is
  the right column, and its time column is the clock instead (`14:05` today, `10-03` before then;
  a finding dated today reads `today`).
- **Ladder**, with `--ladder` (or `l` while watching): the model and effort each role runs on,
  then how many agents of that role `agents.tsv` records and the models their sessions ran on.
  `escalate → fable · xhigh  1 opus` is one escalate agent whose session ran on Opus. Each
  session's model is the first one its log names. A role with no agents shows 0, and an agent
  whose session has no log is counted with no model. From 140 columns it sits at the top of the
  right column, above recent.
- **Legend**: one status vocabulary throughout: ● working, ○ ready, ◐ review or CI running, ✓ done
  or green, ✗ failing, ⏸ blocked, ! needs you (including an agent whose session is gone or unknown, or whose login expired), and ?
  for a herdr state dash does not know (with herdr's word for it).
- **Status bar**, from 140 columns, on the last lines: the merge mode, the summary's counts, today's
  cost, who is on call and today's escalations, the ci line, and the keys (`q` quit, `t` tree, `l` ladder, `r` redraw).

It fits the terminal: it truncates with … rather than wraps, except that a needs-you action wraps
onto an indented line so it is never cut. Under 100 columns it drops the role, model and actor
columns, and when the header does not fit, its version and merge mode go before what comes next.
Each model has a colour of its own, the same wherever it appears (agent rows, the tree, the
ladder): Fable pink, Opus orange, Sonnet blue, Haiku green, codex grey. Colour only on a terminal,
and none at all when `NO_COLOR` is set or the output goes to a pipe or a file; the symbols carry
the same meaning in plain text. If herdr is missing or gives no answer, it
still shows the board and says the agents are unavailable. At 100 columns, from a real project
(the speedometer's numbers are made up for this example):

```text
infrafactory  swarm-dev 0.13.0  merge human  next wait conduct-rehearsal-prepare-gate       12:48:02
1.6 merged/day over 7 days · ! 2 waiting on you, oldest 4h05m · ✓ 0 escaped in 7 days
! 1 intervention in 7 days
14 days ▂▁▃▇▅▁▂▂▃▂▂▃▃▃  today 2  7-day avg 1.6
rate ████████████ 1.6 of best 1.6/day · running ███▓▓▓······ 2 of peak 4 in 7 days
9 epics active · 2 agents working · 1 PRs green, waiting · 0 stalled · $427.69 today
on call: fable·xhigh · 0 escalations today
board: 2 uncommitted edits in the main checkout: stories/prod-read-seam-reader-user.md, stories/fak…
╭─ needs you ──────────────────────────────────────────────────────────────────────────────────────╮
│ ! merge fakeaws#71 (✓ green)  fakeaws-subnet-overlap-refused                                     │
│ ! run lead story prod-read-seam-reader-user: create the read-only reader user and its key file   │
│   waits for: the lead                                                                            │
╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
╭─ epics ──────────────────────────────────────────────────────────────────────────────────────────╮
│ ! prod-read-seam          ██████████░░ 12/15  1 ready · 2 blocked                                │
│ ● rehearsal-prepare-gate  ██████████░░  8/10  1 ready · 1 blocked                                │
│   ● conduct-rehearsal-prepare-gate  conduct    opus·high    working                              │
│   ✓ rehearsal-prepare-second-init   code-risky opus·xhigh   idle                                 │
│ ◐ fakeaws-data-sources    █████████░░░  8/11  1 review · 2 blocked                               │
│   ✓ conduct-fakeaws-data-sources    conduct    opus·high    reported                             │
│   ✓ fakeaws#71                      green  fakeaws-subnet-overlap-refused                        │
│   no epic                                                                                        │
│   ● dash-pretty                     code       opus·high    working                              │
│ ✓ 6 active epics with no open story: fakeaws-loader, rehearsal-against-the-copy, rehearsal-pass… │
╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
⏸ 6 blocked · 9 later  (swarm.sh status --all lists them)
╭─ recent ─────────────────────────────────────────────────────────────────────────────────────────╮
│     today  ✎ 4 findings: /mock/reset and /mock/restore changed the identity wit…        findings │
│     today  ✎ 2 findings: credential file checked with Lstat then re-opened by p…        findings │
│    4m ago  · close learning-router-one-table                                              w1:p5W │
│    4m ago  ⇡ merged #521 story/learning-router-one-table                              redscaresu │
│    4m ago  · tell:findings dash-pretty                                                    w1:p5W │
│    5m ago  · log-finding state-duplication https://github.com/redscaresu/infraf…           wZ:p2 │
│    5m ago  · close fakeaws-subnet-overlap-refused                                          wZ:p8 │
│    5m ago  · review fakeaws-subnet-overlap-refused                                         wZ:p8 │
╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
● working   ○ ready   ◐ review / CI running   ✓ done / green   ✗ failing   ⏸ blocked
! needs you (session gone or unknown)   ? unknown
```

`.swarm/events.tsv` is the local, append-only audit log of what `swarm.sh` did: one line per
command, with the time, the target, the pane that ran it and how it ended (`ok`, `interrupted`, the
error that stopped it, or `failed (exit N)`). Every command writes it except the read-only ones
(`dash`, `status`, `next`, `config`, `policy`, `cost`, `lessons`, `findings`, `wait`, `watch`,
`base`, and `tidy` without `--yes`); `reconcile` and `unblock` write a line per item they move. It
holds names and paths, never the contents of a brief or a message.

`swarm.sh dash --check` draws nothing. It compares each figure in this project's frame (or in each
`--project` frame) with the command that owns it, prints one line per mismatch, such as
`bravo: cost: dash shows 31.20, flow --since 2026-10-18 says 2.80`, and exits 1 if it found any.
It checks the working agents and the running gauge against `swarm.sh status`, the header's next
against the first line of `swarm.sh next`, read without starting the conductors `next` starts, and the epics waiting on their `depends_on` against the rule `next` plans
by. The cost is checked against the `cost` section of `swarm.sh flow --since <today>` with no calling
session, read just before and just after the frame: anything between the two agrees, so agents
spending while it runs is no mismatch. Merges today and the 7-day rate are checked against flow's
`merges` section, the stories finished per day. Every item that flow's `lead_queue` holds open
must show in needs you or the lead's queue (an escalated or held story only with `lead = session`,
the only time dash draws one, and a no-agent item only when status could read herdr's agent list), and so must every PR, every story only you or the lead can run
(those behind `+N more` count) and every agent waiting on a prompt that status lists. flow's
sections run inside the check and ask `gh` nothing. The release arm of `/swarm-dev:swarm` runs it
after each release. `tests/dash_check_test.sh` shows that it agrees on the two-project fixture, with
`lead = off` too, and fails when one of the fixes for the 2026-10-17 dash defects is reverted.

`tests/dash_golden_test.sh` draws a fixed two-project board (`tests/fixtures/dash/two_projects.sh`)
at 60, 100 and 200 columns and compares each frame with `tests/fixtures/dash/golden-<cols>.txt`.
The fixture sets `SWARM_DASH_NOW`, which fixes dash's clock, so the frames come out the same on
every run. If you change what dash draws, run `UPDATE_GOLDEN=1 bash tests/dash_golden_test.sh` and
commit the regenerated frames in the same PR, so the review shows the new look as a diff.

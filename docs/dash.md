# Watching the swarm

`swarm.sh dash` prints one screen of what the swarm is doing; `swarm.sh dash --watch [seconds]`
keeps it open and redraws it in place every 2 seconds (or the seconds you give), repainting only
when something changed. Press `q` to quit (Ctrl-C works too), `r` to redraw, `t` to switch to the
agents by herdr workspace and tab and back, and `l` to show the model per role; resizing the
terminal redraws it at the new size. It works in any terminal, inside herdr or not: it only reads,
so it asks herdr for the agents whenever `herdr` is on your PATH. It never changes the board, the
state or the logs, and never opens or closes a pane. In a folder with no board it stops with one line
naming `swarm.sh init`.

To watch more than one project, name each with `--project <dir>`: `swarm.sh dash --project
~/src/app --project ~/src/infra` draws app's screen and then infra's, each headed by its project's
name, with the legend once at the bottom. `--watch` on a terminal redraws them together as one
screen, each with its share of the height left above the legend. Anywhere else nothing is cut, as
with plain `dash`. If one project's screen fails to draw, its error takes its place and the others
still show. It checks every folder before it draws anything, and stops at the first one that has
no `.claude/swarm/config` or no board, naming it. With `--project` it shows only the projects you
name, so you can run it from any git repo, even one with no board of its own.

When `claude plugin update` installs a new version while `--watch` runs from the installed plugin,
the watch switches to the new version's `swarm.sh` before its next frame and keeps your `t` and `l`
choices. It reads the version from Claude Code's `installed_plugins.json`. Run from a checkout of
this repo, it never switches.

In a terminal at least 140 columns wide it splits into two columns: needs you and the epics on
the left, recent as a timestamped log on the right, and a status bar on the last line. Narrower, it
is one column, top to bottom:

- **Header**: the project, the swarm-dev version, the `merge` mode, what `/swarm-dev:swarm` does next, and the
  time of the last refresh. Under it, at every width, the speedometer: `2.0 merged/day over 7 days`
  is the number of stories the swarm finished in the last 7 days, divided by 7. dash reads them from
  `events.tsv`: a `finish` line, or `reconcile`'s `finished` line once a story's PR merged, each slug
  counted once. A story that was dropped or rescoped writes neither, so it never counts. It asks gh
  nothing. Two lights follow it,
  each `!` and lit when its count is above 0, `✓ 0` when not. The first counts what waits on you
  (or on you or the lead, with `lead = session`): every row in needs you and the lead's queue, plus
  the stories behind `+N more`. It also says how long the oldest one has waited: a board item waits
  from its newest `review`, `close:<cause>` or `escalated` line in `events.tsv`, or else from its
  file's last commit. The second counts the escaped defects logged in the last 7 days
  (`--reviewer escaped` in `findings.tsv`). Then one summary line: epics active, agents working, PRs green and
  waiting for you, stalled builders, and today's estimated cost (the `cost` section of `swarm.sh flow --since <today>`). After
  it comes who is on call (`on call: fable·xhigh`, the escalate role's model and effort, or `on
  call: off` with `escalate_after = 0`) and how many builds escalated to it today (`0 escalations
  today` too), on the same line when they fit there and on the next line when they don't. Then a
  warning when the main checkout has board edits not committed yet, naming the files, cut to the
  width: `board: 2 uncommitted edits in the main checkout: stories/a.md, stories/b.md`. From 140
  columns the merge mode, the summary and who is on call move to the status bar.
- **Needs you**: only what you act on, one short action a line: `merge` a PR (with its checks and
  whether it is behind the base), `run` a `lead` story (with its title), `answer` an agent waiting
  on a prompt (with what its session waits for), `auth: run /login` for an agent whose login expired (it is idle, but only your `/login` clears it), `close` an empty pane, `look at` an agent whose session is gone or unknown, `look at` a stalled agent (working for `stall_minutes`, 30
  by default, with no sign of life: for any agent with a Claude session no write to its session log, for a builder also no commit or uncommitted edit in its worktree, PR update or swarm action on its story,
  for an agent with no story (a conductor or planner) no `events.tsv` line naming it or run from its
  pane, nudges and failed tells excepted), `agree` a draft HLD. A `lead` story's row ends with
  who it waits for: `waits for: you: create the read-only user`, with the text of its first
  **You:** line, or `waits for: the lead` when it has none. Only your next **You:** step is listed,
  the first ready `lead` story that has one, with `+N more` when other stories have one too. When
  nothing needs you, it is one line.
- **Lead's queue**, only with `lead = session` in the config: a lead session acts for you, so needs
  you keeps only your steps (`run` a story with a **You:** step, `auth`, `agree` a draft HLD) and
  everything else from the list above moves to this box under it: every `merge`, `answer`, `close`
  and `look at` row, a `lead` story with no **You:** step (`waits for: the lead`), and `decide` for
  every escalated `lead` story (`swarm.sh reset` or `swarm.sh drop`). It is left out when empty.
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
  ones. A finished story's file is deleted, so finished ones are
  counted from the board repo's history: story files deleted on its base branch (and on HEAD) whose
  front matter named the epic, once per slug, when any deletion closed the story: its own PR's
  merge (the commit names `story/<slug>`), its own work (a squash merge: the commit also changes a
  file that is neither the board's own, its `stories/`, `epics/`, `Board.base` and `README.md`, nor
  a root `*.md`, and names no `board/`, `close/` or `epic/` branch),
  the swarm's logged `finish`, or a last status of `done` or `review` or a `prs:` line. A story
  still on the board here is open, and a re-scope counts as nothing. The row's symbol is ○
  when stories are ready and nothing runs, and ⏸ only when every remaining story is blocked or later. Under it, its live agents (role, model and effort, status) and its open PRs. A working
  agent's status carries how long since its last sign of life (`working 12m`), and past
  `stall_minutes` it reads `stalled 40m`, marked `!`. From
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
  epics with no open story share one line. Blocked and later items are one count line under it;
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
  cost, who is on call and today's escalations, and the keys (`q` quit, `t` tree, `l` ladder, `r` redraw).

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

`tests/dash_golden_test.sh` draws a fixed two-project board (`tests/fixtures/dash/two_projects.sh`)
at 60, 100 and 200 columns and compares each frame with `tests/fixtures/dash/golden-<cols>.txt`.
The fixture sets `SWARM_DASH_NOW`, which fixes dash's clock, so the frames come out the same on
every run. If you change what dash draws, run `UPDATE_GOLDEN=1 bash tests/dash_golden_test.sh` and
commit the regenerated frames in the same PR, so the review shows the new look as a diff.

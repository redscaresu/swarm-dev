# Watching the swarm

`swarm.sh dash` prints one screen of what the swarm is doing; `swarm.sh dash --watch [seconds]`
keeps it open and redraws it in place every 2 seconds (or the seconds you give), repainting only
when something changed. Press `q` to quit (Ctrl-C works too), `r` to redraw, `t` to switch to the
agents by herdr workspace and tab and back, and `l` to show the model per role; resizing the
terminal redraws it at the new size. It works in any terminal, inside herdr or not: it only reads,
so it asks herdr for the agents whenever `herdr` is on your PATH. It never changes the board, the
state or the logs, and never opens or closes a pane.

In a terminal at least 140 columns wide it splits into two columns: needs you and the epics on
the left, recent as a timestamped log on the right, and a status bar on the last line. Narrower, it
is one column, top to bottom:

- **Header**: the project, the swarm-dev version, the `merge` mode, what `/swarm-dev:swarm` does next, and the
  time of the last refresh. Under it, one summary line: epics active, agents working, PRs green and
  waiting for you, stalled builders, and today's estimated cost (`swarm.sh cost` for today). After
  it comes who is on call (`on call: fable·xhigh`, the escalate role's model and effort, or `on
  call: off` with `escalate_after = 0`) and how many builds escalated to it today (`0 escalations
  today` too), on the same line when they fit there and on the next line when they don't. Then a
  warning when the main checkout has board edits not committed yet. From 140 columns the merge
  mode, the summary and who is on call move to the status bar.
- **Needs you**: only what you act on, one short action a line: `merge` a PR (with its checks and
  whether it is behind the base), `run` a `lead` story (with its title), `answer` an agent waiting
  on a prompt (with what its session waits for), `auth: run /login` for an agent whose login expired (it is idle, but only your `/login` clears it), `close` an empty pane, `look at` an agent whose session is gone or unknown, `look at` a stalled builder (working for `stall_minutes`, 30
  by default, with no commit, PR update or swarm action), `agree` a draft HLD. When nothing does,
  it is one line.
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
  when stories are ready and nothing runs, and ⏸ only when every remaining story is blocked or later. Under it, its live agents (role, model and effort, status) and its open PRs. From
  140 columns each agent is a card: the model and effort sit on a label in the model's colour, and
  a working agent shows how long ago it started (its `story`, `conduct` or `agent` line in
  `events.tsv`). An escalate agent also shows which attempt its Fable build is and when it
  started, from its newest `escalate` line (`attempt 3 · 14:02`). Idle and
  retired agents not on an open story are one `+N idle` line; agents on no epic come last. Active
  epics with no open story share one line. Blocked and later items are one count line under it;
  `swarm.sh status --all` lists them. `--tree` (or `t` while watching) shows every agent by herdr
  workspace and tab instead.
- **Recent**: newest first, with how long ago (`4m ago`, `2h ago`; a dated finding in calendar
  days, `today`, `yesterday`, `3d ago`): merges on the base branch (⇡), review findings
  fixed (✎, one row per PR and day), agents, conductors and builders started (▶), escalation
  steps (▲: `escalate`, `dialog`, `escalated`, `reset` and `drop`), and the swarm's other actions
  (·); a failed one is ✗. It fills the rest of the screen. From 140 columns it is
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
still shows the board and says the agents are unavailable. At 100 columns, from a real project:

```text
infrafactory  swarm-dev 0.13.0  merge human  next wait conduct-rehearsal-prepare-gate       12:48:02
9 epics active · 2 agents working · 1 PRs green, waiting · 0 stalled · $427.69 today
on call: fable·xhigh · 0 escalations today
board: 2 uncommitted edits in the main checkout (reconcile pulls first)
╭─ needs you ──────────────────────────────────────────────────────────────────────────────────────╮
│ ! merge fakeaws#71 (✓ green)  fakeaws-subnet-overlap-refused                                     │
│ ! run lead story prod-read-seam-reader-user: create the read-only reader user and its key file   │
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

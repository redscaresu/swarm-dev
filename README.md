# swarm-dev

[![CI](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml/badge.svg)](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/redscaresu/swarm-dev/badge)](https://scorecard.dev/viewer/?uri=github.com/redscaresu/swarm-dev)

**A team of Claude Code agents that builds software while you watch.**

You write a design with one agent. Other agents plan the work, try to break the plan, and build it in
parallel. Each agent runs in its own terminal pane, so nothing happens out of sight. The run stops
whenever a decision is yours.

| Command | What it does |
|---|---|
| `/hld <title>` | Write the design with an agent. |
| `/swarm` | Do everything after that. When it stops for you, decide, then run it again. |

## How it works

```
/hld ──▶ 1. Design      written with you, then attacked by a reviewer
                         ◆ you agree it
/swarm ─▶ 2. Epics       the design split into goals; agents argue about the split
                         ◆ you approve them
          3. Stories     each goal split into PR-sized pieces; a skeptic attacks each
                         ◆ you approve them
          4. Build       one builder per agent story, own worktree, reviewed, CI green
                         ◆ you merge

◆ = the run stops for you
```

| Who | Does |
|---|---|
| **You** | Agree the design, approve the plan, merge, and any step only a person can take. |
| **Your Claude session (the lead)** | Anything touching real cloud or credentials, and the checks around your steps. |
| **Agents** | Planning, reviews, code, docs and tests. Never real cloud or credentials. |

Planning lists your steps before you approve anything. Stories your session runs are `kind: lead`,
and your own steps in them are marked **You:**. More: [`docs/method.md`](docs/method.md).

## Three feedback loops

| Loop | When | What it does |
|---|---|---|
| **Inner** | while a builder works | For a code change, the builder proves each new test can fail: it breaks the fix, sees the test fail, and restores it. A test that passes with its fix removed proves nothing. |
| **Middle** | before a builder is closed | Each PR passes `codex` and, if it changes code, the `/code-review` skill. The conductor sends findings back to the builder that wrote the code (`swarm.sh tell`), which still has its context, and closes it at the first pass with nothing substantive: only nits, out-of-scope edge cases, or points already declined. |
| **Outer** | across epics | Each fixed finding is logged by kind (`swarm.sh log-finding`). `swarm.sh lessons` names a kind that keeps coming back in 3+ PRs, or a lead memory you tagged `lesson: <kind>` in its frontmatter (builders run in their own worktrees and never see the lead's memory), and `/swarm` proposes a one-line rule for your `lessons_file` (default `.claude/swarm/brief.md`, which every brief includes; or `AGENTS.md`, which every agent and you already load) as a PR you approve; a rule PR you close is not proposed again. |

## Getting started

**1. Install the tools.** [Claude Code](https://claude.com/claude-code), [herdr](https://herdr.dev)
(the panes), the [GitHub CLI](https://cli.github.com) and the [codex CLI](https://github.com/openai/codex),
both logged in, plus `git`, `python3` and `bash`. Your code lives in git repos with `origin` on GitHub.

**2. Install the plugin**, then restart Claude Code:

```bash
claude plugin marketplace add redscaresu/swarm-dev && claude plugin install swarm-dev@swarm-dev
```

**3. Add the board to your project.** From the project's root:

```bash
git clone --depth 1 https://github.com/redscaresu/swarm-dev /tmp/swarm-dev
mkdir -p docs .claude/swarm && cp -Rn /tmp/swarm-dev/templates/docs/. docs/
printf '.swarm/\ndocs/.obsidian/*\n!docs/.obsidian/app.json\n' >> .gitignore
```

Then run `claude` once in the repo and accept the "do you trust this folder?" prompt. Agents work in
git worktrees of that repo, and an untrusted repo would leave them stuck on that prompt, so
`swarm.sh` refuses to start until you have.

**4. Run it.** Inside herdr, start `claude` and write a design with `/hld Add rate limiting to the API`.
Talk to the co-author in its pane, say when the draft is ready, fix what the reviewer finds, and say you
agree it. Then run `/swarm`, and run it again each time it stops for you.

That's all you need. Optional extras:

- **Rules for every builder**, such as "Run `make test` before opening a PR": put them in
  `.claude/swarm/brief.md`. List shared files (root config, schemas, CI scripts) in `AGENTS.md`, so no
  two stories edit them at once.
- **Settings** go in `.claude/swarm/config`, one `key = value` per line. The common ones are
  `merge = agent` (the conductor merges green, reviewed PRs), `base_branches = dev main`,
  `pr_per = epic` and `lessons_file = AGENTS.md`. `swarm.sh config` shows what's in effect; all of them
  are in [`docs/method.md` § Configuring a project](docs/method.md#configuring-a-project).
- **See the board** in [Obsidian](https://obsidian.md) 1.9+: open the board folder as a vault, then
  `Board.base`. **Waiting on you** lists your `lead` stories. If the views don't show, turn on
  **Bases** under Core plugins.
- **Check on it** with `swarm.sh status`: the agents that need a look, what waits on you, and what
  `/swarm` does next. `swarm.sh tidy --yes` closes panes that hold nothing to read.
- **Watch it** on one screen with `swarm.sh dash`, or `swarm.sh dash --watch` to keep it open:
  see [Watching the swarm](#watching-the-swarm).
- **On Foundry, Bedrock or Vertex**, agents start as plain `claude` in new panes, so load your
  provider settings in `~/.zshrc` for herdr panes, not in an alias:

  ```bash
  [[ -n "$HERDR_ENV" ]] && claude() { ( source ~/path/to/your-provider-env.sh && command claude "$@" ) }
  ```

## When `/swarm` stops for you

| You see | Do |
|---|---|
| a draft design | finish it with the co-author, then agree it |
| proposed epics or stories | approve them, or say what to change |
| a `lead` story | say go, and do its **You:** steps |
| a PR waiting for you | merge it, or close it to send the story back |
| a `blocked` story | usually nothing: it clears when what it waits on merges |
| a `later` item | set a story `ready`, or an epic `active`, to start it |
| a proposed brief rule (a lesson) | merge the PR to adopt it, or close it |

`swarm.sh status` shows this list any time, with the agents that need a look.

## Watching the swarm

`swarm.sh dash` prints one screen of what the swarm is doing; `swarm.sh dash --watch [seconds]`
keeps it open and redraws it in place every 2 seconds (or the seconds you give), repainting only
when something changed. Press `q` to quit (Ctrl-C works too), `r` to redraw, `t` to switch to the
agents by herdr workspace and tab and back, and `l` to show the model per role; resizing the
terminal redraws it at the new size. It works in any terminal, inside herdr or not: it only reads,
so it asks herdr for the agents whenever `herdr` is on your PATH. It never changes the board, the
state or the logs, and never opens or closes a pane. Top to bottom:

- **Header**: the project, the swarm-dev version, the `merge` mode, what `/swarm` does next, and the
  time of the last refresh. Under it, one summary line: epics active, agents working, PRs green and
  waiting for you, stalled builders, and today's estimated cost (`swarm.sh cost` for today); then a
  warning when the main checkout has board edits not committed yet.
- **Needs you**: only what you act on, one short action a line: `merge` a PR (with its checks and
  whether it is behind the base), `run` a `lead` story (with its title), `answer` an agent waiting
  on a prompt, `close` an empty pane, `look at` a stalled builder (working for `stall_minutes`, 30
  by default, with no commit, PR update or swarm action), `agree` a draft HLD. When nothing does,
  it is one line.
- **Epics**: one row per active epic, with a bar of its finished stories out of all of them and how
  many open stories are in each status. A finished story's file is deleted, so finished ones are
  counted from the board repo's history: story files deleted on its base branch (and on HEAD) whose
  front matter named the epic, once per slug, when any deletion closed the story: its own PR's
  merge (the commit names `story/<slug>`), the swarm's logged `finish`, or a last status of `done`
  or `review` or a `prs:` line. A story still on the board here is open; a re-scope counts as
  nothing, whatever else its commit changes, and so does a squash merge the swarm did not log. The row's symbol is ○
  when stories are ready and nothing runs, and ⏸ only when every remaining story is blocked or later. Under it, its live agents (role, model and effort, status) and its open PRs. Idle and
  retired agents not on an open story are one `+N idle` line; agents on no epic come last. Active
  epics with no open story share one line. Blocked and later items are one count line under it;
  `swarm.sh status --all` lists them. `--tree` (or `t` while watching) shows every agent by herdr
  workspace and tab instead.
- **Recent**: newest first, with how long ago (`4m ago`, `2h ago`; a dated finding in calendar
  days, `today`, `yesterday`, `3d ago`): merges on the base branch (⇡), review findings
  fixed (✎, one row per PR and day), agents, conductors and builders started (▶), and the swarm's
  other actions (·); a failed one is ✗. It fills the rest of the screen.
- **Ladder**, with `--ladder` (or `l` while watching): the model and effort each role runs on.
- **Legend**: one status vocabulary throughout: ● working, ○ ready, ◐ review or CI running, ✓ done
  or green, ✗ failing, ⏸ blocked, ! needs you, and ? for an agent state dash does not know (with
  herdr's word for it).

It fits the terminal: it truncates with … rather than wraps, except that a needs-you action wraps
onto an indented line so it is never cut. Under 100 columns it drops the role, model and actor
columns, and when the header does not fit, its version and merge mode go before what comes next.
From 140 columns a shown ladder sits beside recent. Colour only on a terminal, unless `NO_COLOR` is
set; the symbols carry the same meaning in plain text. If herdr is missing or gives no answer, it
still shows the board and says the agents are unavailable. At 100 columns, from a real project:

```text
infrafactory  swarm-dev 0.13.0  merge human  next wait conduct-rehearsal-prepare-gate       12:09:12
9 epics active · 3 agents working · 0 PRs green, waiting · 0 stalled · $417.17 today
board: 1 uncommitted edit in the main checkout (reconcile pulls first)
╭─ needs you ──────────────────────────────────────────────────────────────────────────────────────╮
│ ! run lead story prod-read-seam-reader-user: create the read-only reader user and its key file   │
╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
╭─ epics ──────────────────────────────────────────────────────────────────────────────────────────╮
│ ! prod-read-seam          ██████████░░ 12/15  1 ready · 2 blocked                                │
│ ● fakeaws-data-sources    ████████░░░░  7/11  1 ready · 3 blocked                                │
│   ● fakeaws-describe-availability…  code-risky opus·xhigh   working                              │
│ ● rehearsal-prepare-gate  ██████████░░  8/10  1 ready · 1 blocked                                │
│   ● rehearsal-prepare-second-init   code-risky opus·xhigh   working                              │
│   no epic                                                                                        │
│   ● dash-pretty                     code       opus·high    working                              │
│   ✓ learning-router-one-table       code-risky opus·xhigh   idle                                 │
│ ✓ 6 active epics with no open story: fakeaws-loader, rehearsal-against-the-copy, rehearsal-pass… │
│ +2 idle  (--tree lists them)                                                                     │
╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
⏸ 7 blocked · 9 later  (swarm.sh status --all lists them)
╭─ recent ─────────────────────────────────────────────────────────────────────────────────────────╮
│     today  ✎ 4 findings: /mock/reset and /mock/restore changed the identity wit…        findings │
│     today  ✎ 2 findings: credential file checked with Lstat then re-opened by p…        findings │
│       now  ✗ tell rehearsal-prepare-second-init: rehearsal-prepare-second-init …           wZ:p2 │
│    1m ago  ⇡ merged #523 board/az-ready                                               redscaresu │
│    2m ago  · tell fakeaws-describe-availability-zones                                      wZ:p6 │
│    7m ago  · tell rehearsal-prepare-second-init                                            wZ:p2 │
│   11m ago  · close fakeaws-kms-store-follows-lifecycle                                    w1:p5W │
│   12m ago  · tell dash-pretty                                                             w1:p5W │
╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
● working   ○ ready   ◐ review / CI running   ✓ done / green   ✗ failing   ⏸ blocked   ! needs you
? unknown
```

`.swarm/events.tsv` is the local, append-only audit log of what `swarm.sh` did: one line per
command, with the time, the target, the pane that ran it and how it ended (`ok`, `interrupted`, the
error that stopped it, or `failed (exit N)`). Every command writes it except the read-only ones
(`dash`, `status`, `next`, `config`, `policy`, `cost`, `lessons`, `findings`, `wait`, `watch`,
`base`, and `tidy` without `--yes`); `reconcile` and `unblock` write a line per item they move. It
holds names and paths, never the contents of a brief or a message.

## Updating

`/swarm` tells you when a new version is out. From the Claude Code prompt:

```
! claude plugin marketplace update swarm-dev
```

```
! claude plugin update swarm-dev@swarm-dev
```

Then restart Claude Code (`claude --continue` resumes your conversation).

## Cost and safety

- **Tokens.** Every agent is a full Claude Code session, on a model picked by its role: Fable for
  the design, Opus for planning judgment, building code and conducting, Sonnet for surveys and
  docs, Haiku for verification and chores (`swarm.sh policy <role>`). Planning one epic starts
  about ten agents; give the planner an existing survey and it starts one survey agent instead of
  three. Each agent story gets one builder, and its review rounds go back to that builder.
  `swarm.sh cost` shows where the tokens went.
- **Codex limits.** When codex hits its usage limit, nothing waits for the reset: the review goes
  on with `/code-review` and the conductor's own reading, and the PR says codex was skipped.
- **Logins.** Agents use your own `claude`, `codex`, `gh` and `git` logins.
- **Merging.** By default no agent merges: every green, reviewed PR waits for you.
- **Scope.** No agent gets a story that needs real cloud, credentials or your judgment.

Details and reporting a vulnerability: [`SECURITY.md`](SECURITY.md). Agents, and anyone working on
swarm-dev itself: [`AGENTS.md`](AGENTS.md).

## License

Apache-2.0.

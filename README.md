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
when something changed. Press `q` to quit (Ctrl-C works too) and `r` to redraw; resizing the
terminal redraws it at the new size. It works in any terminal, inside herdr or not: it only reads,
so it asks herdr for the agents whenever `herdr` is on your PATH. It never changes the board, the
state or the logs, and never opens or closes a pane. What it shows:

- **Header**: one line with the project, the swarm-dev version, the `merge` mode, today's estimated
  cost (`swarm.sh cost` for today), what `/swarm` does next, and the time of the last refresh.
- **Pipeline**: one line of how many HLDs, epics and stories are in each status, and a warning when
  the main checkout has board edits not committed yet.
- **Agents**: this project's agents, by herdr workspace and tab (a conductor's tab is its epic),
  each with its role, model and effort, its status, and its story's PR. `!` marks one that needs a
  look: waiting on a prompt, or an empty pane where a start failed. A conductor that wrote its
  report, not yet collected, shows `[reported]`. A story's builder that has shown working for
  `stall_minutes` (30 by default) with no commit, PR update or swarm action shows `[stalled?]`.
- **Waiting on you**: only what needs you: PRs awaiting your merge (with their checks, ✔ green,
  ✘ red or ● running, and `behind` or `dirty` against the base), `lead` stories, draft HLDs and
  stalled builders.
  Blocked and later items are one count line; `swarm.sh status --all` lists them.
- **Ladder**: the model and effort each role runs on.
- **Recent**: newest first, the swarm's own actions (the audit log), merges on the base branch, and
  review findings fixed (one row per PR and day). It fills the rest of the screen.

It fits the terminal: it truncates rather than wraps, and from 140 columns it puts the ladder and
recent side by side. Colour only on a terminal, unless `NO_COLOR` is set. If herdr is missing or
gives no answer, it still shows the board and says the agents are unavailable. Trimmed to 100
columns, from a real project:

```text
infrafactory  swarm-dev 0.12.0  merge human  today $108.48  next wait conduct-fakeaws-load… 00:22:53
HLDs agreed 2 superseded 1  ·  epics active 12 later 2  ·  stories ready 4 blocked 18 later 7
┌─ agents ─────────────────────────────────────────────────────────────────────────────────────────┐
│ 2026-09-30-import-production-state-into-the-mocks                                                │
│  ├─ fakeaws-loaded-identity                                                                      │
│  │  ├─   conduct-fakeaws-loaded-identi…  conduct    opus·high     [done]                         │
│  │  └─   fakeaws-identity-other-servic…  code       opus·high     [working]                      │
│  └─ prod-read-seam                                                                               │
│     ├─   conduct-prod-read-seam          conduct    opus·high     [done]                         │
│     ├─   prod-read-seam-wall             code-risky opus·xhigh    [working]                      │
│     └─   prod-read-seam-credentials      code-risky opus·xhigh    [done]                         │
│ infrafactory                                                                                     │
│  └─ scope-fakeaws-rehearsal-instance                                                             │
│     └─   lead-fri                        lead       opus·xhigh    [idle]                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
┌─ waiting on you ─────────────────────────────────────────────────────────────────────────────────┐
│ nothing                                                                                          │
│ blocked 18 · later 9 (swarm.sh status --all lists them)                                          │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
┌─ ladder ─────────────────────────────────────────────────────────────────────────────────────────┐
│ hld        → fable · high     hld-review → fable · xhigh    hld-lead   → fable · xhigh           │
│ survey     → sonnet · high    lead       → opus · xhigh     skeptic    → opus · high             │
│ critic     → opus · high      codex      → codex · high     code       → opus · high             │
│ code-risky → opus · xhigh     docs       → sonnet · medium  chore      → haiku · medium          │
│ verify     → haiku · medium   escalate   → fable · xhigh    conduct    → opus · high             │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
┌─ recent ─────────────────────────────────────────────────────────────────────────────────────────┐
│ 10-12 00:15  wX:p2           tell fakeaws-identity-other-services                           [ok] │
│ 10-12 00:06  wX:p5           story prod-read-seam-credentials                               [ok] │
│ 10-12 00:06  wX:p5           story prod-read-seam-wall                                      [ok] │
│ 10-12 00:06  w1:p5W          conduct prod-read-seam                                         [ok] │
│ 10-12 00:06  w1:p5W          close conduct-prod-read-seam                                   [ok] │
│ 10-12 00:05  redscaresu      merged #468 board/wave-after-adr-0041                       [merge] │
│ 10-12 00:04  redscaresu      merged #406 board/ui-e2e-run-mode-noise                     [merge] │
│ 10-11        review          2 findings: tofu helper ran with no deadline, so a key…  [findings] │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
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

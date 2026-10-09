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
| **Middle** | before a builder is closed | Each PR passes `codex` and, if it changes code, the `/code-review` skill. The conductor sends findings back to the builder that wrote the code (`swarm.sh tell`), which still has its context, and closes it only once a pass is clean. |
| **Outer** | across epics | Each fixed finding is logged by kind (`swarm.sh finding`). `swarm.sh lessons` names a kind that keeps coming back in 3+ PRs, and `/swarm` proposes a one-line rule for your `.claude/swarm/brief.md`, which every agent reads, as a PR you approve; a declined rule is not proposed again. |

## Getting started

**1. Install the tools.** [Claude Code](https://claude.com/claude-code),
[herdr](https://herdr.dev) (the panes), the [GitHub CLI](https://cli.github.com) and the
[codex CLI](https://github.com/openai/codex) (both logged in), [Obsidian](https://obsidian.md) 1.9+
(to see the board), plus `git`, `python3` and `bash`. Your code must be in git repos with `origin` on
GitHub.

**2. Install the plugin**, then restart Claude Code:

```bash
claude plugin marketplace add redscaresu/swarm-dev
```

```bash
claude plugin install swarm-dev@swarm-dev
```

**3. Set up your project.** From its root, copy in the board templates:

```bash
git clone --depth 1 https://github.com/redscaresu/swarm-dev /tmp/swarm-dev
```

```bash
mkdir -p docs .claude/swarm
```

```bash
cp -Rn /tmp/swarm-dev/templates/docs/. docs/
```

Add `.swarm/` and `docs/.obsidian/*` to `.gitignore` (but keep `!docs/.obsidian/app.json`). Write `.claude/swarm/brief.md` with the rules
every builder must follow, for example "Run `make test` before opening a PR". List shared files
(root config, schemas, CI scripts) in `AGENTS.md`, so no two agents edit them at once.

**Trust each repo in Claude Code once.** Run `claude` in the repo's main checkout and accept the
"do you trust this folder?" prompt. Agents build in new git worktrees, and Claude Code checks a
worktree's trust on its main checkout. Trusting a parent folder such as `~/Work` does not cover a
repo inside it. `swarm.sh` refuses to start an agent in a repo you have not trusted and names the
folder, so the agent cannot stall on that prompt.

**4. Change settings, if you want**, in `.claude/swarm/config` (`key = value` per line):

| Setting | Default | Common change |
|---|---|---|
| `board_dir` | `docs` | a board elsewhere, even outside git, if every story names its `repo:` |
| `base_branches` | origin's default | `dev main`: branch from `dev` where it exists |
| `merge` | `human` | `agent`: the conductor (the agent building an epic) merges green, reviewed PRs |
| `pr_per` | `story` | `epic`: one PR per epic |
| `keep_panes` | `false` | `true`: keep finished panes open (renamed `<name>-done`) |

The rest: [`docs/method.md` § Configuring a project](docs/method.md#configuring-a-project).
`swarm.sh config` shows what is in effect.

**5. Open the board.** In Obsidian, open your board folder as a vault, then `Board.base`. The
**Waiting on you** view lists your `lead` stories. If the views don't show, turn on **Bases** under
Core plugins.

**6. Write a design.** In herdr, start `claude` and run `/hld Add rate limiting to the API`. Talk to
the co-author in its pane. Say when the draft is ready, fix what the reviewer finds, then say you
agree it. Run `/hld` alone to carry on later. Guide:
[`docs/method.md` § Writing the HLD](docs/method.md#writing-the-hld).

**7. Run `/swarm`.** Watch any pane, or the board. `swarm.sh next` shows what it would do next.

**Not sure what's going on?** Run `swarm.sh status`. It lists the agents that need a look: working,
waiting on a question, or **empty** (an agent that never started, so close that pane). It counts idle
agents and blocked stories, shows what is waiting on you, and what `/swarm` would do next. Add `--all`
to list everything. `swarm.sh tidy` lists the panes it can close (empty ones, and finished agents kept open by
`keep_panes`); `swarm.sh tidy --yes` closes them. It never touches a working, waiting or idle agent.

**Using Foundry, Bedrock or Vertex?** Agents start as plain `claude` in new panes, so load your
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

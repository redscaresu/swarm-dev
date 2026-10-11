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

# swarm-dev

[![CI](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml/badge.svg)](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/redscaresu/swarm-dev/badge)](https://scorecard.dev/viewer/?uri=github.com/redscaresu/swarm-dev)

swarm-dev runs a team of Claude Code agents that build software while you watch. You write a design
with one agent. Others plan it, try to break the plan, and build it in parallel, each in its own
terminal pane. The run stops whenever a decision is yours.

![swarm.sh dash --watch on a demo project: what needs you and the epics on the left, recent work on the right](docs/assets/dash.gif)

## How it works

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/swarm-flow-dark.png">
  <img alt="How the swarm builds a design: /hld, /swarm, /plan-hld, /plan-epic, the board, conductor, builders, review, merge" src="docs/assets/swarm-flow-light.png">
</picture>

1. You write a high-level design (HLD) with a co-author agent.
2. A planning swarm splits the design into epics, then each epic into stories of one PR
   each. Skeptic agents and codex try to break every plan before you see it, and you approve it.
3. A conductor agent takes an epic and starts one builder per story, each in its own git
   worktree and pane. Each PR is reviewed by codex and `/code-review`, and the builder fixes what
   they find.
4. Green, reviewed PRs wait for you to merge, and the next stories start.

Your own Claude session is the lead. It runs `/swarm`, keeps an eye on the agents, and handles
`kind: lead` stories: real cloud, credentials and anything hard to undo. Your steps in those
stories are marked **You:**.

When reviews keep finding the same kind of problem across PRs, `/swarm`
proposes a one-line rule for future builders, as a PR titled `lesson: <kind>`. You merge it
or close it.

Everything is plain Markdown in `docs/` (the board), so a run can stop anywhere and the next
`/swarm` picks up where it left off. The full method is in [`docs/method.md`](docs/method.md).

## Requirements

- [Claude Code](https://claude.com/claude-code) 2.1.145 or later
- [herdr](https://herdr.dev), the terminal multiplexer every agent runs in
- the [GitHub CLI](https://cli.github.com) and the [codex CLI](https://github.com/openai/codex), both logged in
- `git`, `python3` and `bash`

[Obsidian](https://obsidian.md) is optional: it shows the board as a vault, grouped by status.

![The board in Obsidian, grouped by status](docs/assets/board.png)

## Getting started

1. Install the plugin, then restart Claude Code:

   ```bash
   claude plugin marketplace add redscaresu/swarm-dev && claude plugin install swarm-dev@swarm-dev
   ```

2. In your project's root, run `claude` once and accept "do you trust this folder?". Agents work in
   worktrees of the repo and can't start until it is trusted.
3. Inside herdr, run `claude`, then `/swarm`. The first time, it offers to set up the board and asks
   once for your rules for builders (commit trailers, where credentials live, commands that must
   never run). Commit the `.claude/swarm/brief.md` it writes.
4. Run `/hld Add rate limiting to the API`, agree the design with the co-author, then run `/swarm`
   again. Run it each time it stops for you.

Your agent can also answer "how do I use swarm-dev?" and "why did /swarm stop?".

| Command | What it does |
|---|---|
| `/hld <title>` | Write a design with a co-author agent. |
| `/swarm` | Run everything after the design, stopping when a decision is yours. |
| `swarm.sh status` | Show agents that need a look, what waits on you, and what runs next. |
| `swarm.sh dash --watch` | Open the live dashboard shown above ([details](docs/dash.md)). |
| `swarm.sh cost` | Show where the tokens went. |
| `swarm.sh outcomes` | One row per build: model, cost, review rounds, and whether it merged. |

Settings such as `merge = agent` go in `.claude/swarm/config`
([all settings](docs/method.md#configuring-a-project)). On Foundry, Bedrock or Vertex, load your
provider settings in `~/.zshrc` so herdr panes pick them up. An alias won't reach them:

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
| a `blocked` or `later` item | nothing, or set it `ready` / `active` to start it |
| a proposed rule (`lesson: <kind>`) | merge to adopt it, or close it |
| an agent's login expired | run `/login`, then tell `/swarm` it's done |

## Cost and safety

Every agent is a full Claude Code session, on a model chosen by its role, and planning one epic
starts about ten agents. Agents use your own `claude`, `codex`, `gh` and `git` logins and never
touch real cloud or credentials. By default no agent merges.

`swarm.sh close` keeps a copy of each closed agent's session log in `.swarm/sessions/`, because
Claude Code deletes them after 30 days. The copy is not redacted, so it can hold secrets the session
saw. Only your user can read it, and `.swarm/` is git-ignored, so it never leaves your machine.

`/swarm` tells you when a new version is out. To update, run
`! claude plugin marketplace update swarm-dev`, then `! claude plugin update swarm-dev@swarm-dev`,
and restart. See [`SECURITY.md`](SECURITY.md) for security and [`AGENTS.md`](AGENTS.md) for working
on swarm-dev itself.

## License

Apache-2.0.

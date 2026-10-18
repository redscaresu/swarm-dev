# swarm-dev

[![CI](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml/badge.svg)](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/redscaresu/swarm-dev/badge)](https://scorecard.dev/viewer/?uri=github.com/redscaresu/swarm-dev)

swarm-dev runs a team of Claude Code agents that build software while you watch. You agree a design
with one agent. Others split it into one-PR stories, try to break the plan, and build the stories in
parallel, each in its own terminal pane and git worktree. Every PR is reviewed before it merges, and
the run stops whenever a decision is yours.

![swarm.sh dash --watch on a demo project: what needs you and the epics on the left, recent work on the right](docs/assets/dash.gif)

## How it works

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/swarm-flow-dark.png">
  <img alt="How the swarm builds a design: /hld, /swarm-dev:swarm, /plan-hld, /plan-epic, the board, conductor, builders, review, merge" src="docs/assets/swarm-flow-light.png">
</picture>

1. **Design.** You write a draft epic with a co-author agent (`/epic`): the problem with its
   evidence, goals that can be checked, non-goals and constraints. A reviewer agent attacks it, and
   nothing plans it until you agree it.
2. **Plan.** Once you agree the epic, planning agents (`/plan-epic`) split it into stories of one
   PR each, and skeptic agents try to break the plan. You approve it.
3. **Build.** A conductor agent starts one builder per story. Each PR gets its own review agent,
   and the builder fixes what it finds.
4. **Merge.** Green, reviewed PRs wait for you to merge, or the conductor merges them if you set
   `merge = agent`. Anything marked `costs: money` always waits for you. In a swarm project, a
   plugin hook refuses careless raw merges (`gh pr merge` and GitHub's merge API) in every Claude
   session, so merges go through `swarm.sh merge`. It also refuses a `cd` followed by `;`, a
   `git checkout` that would drop uncommitted changes, and an agent's `git checkout`, `stash` or
   `reset --hard` in the main checkout.

Your own Claude session is the lead. It runs `/swarm-dev:swarm`, watches the agents, and handles
the stories no agent may do: real cloud, credentials and anything hard to undo. Your steps in those
are marked **You:**. Everything lives in plain Markdown files (the board), so a run can stop
anywhere and the next `/swarm-dev:swarm` picks up where it left off.

## Requirements

- [Claude Code](https://claude.com/claude-code) 2.1.145 or later (2.1.269 or later with `goal` on)
- [herdr](https://herdr.dev), the terminal multiplexer every agent runs in
- the [GitHub CLI](https://cli.github.com) and the [codex CLI](https://github.com/openai/codex), both logged in
- `git`, `python3` and `bash`

## Getting started

1. Install the plugin, then restart Claude Code:

   ```bash
   claude plugin marketplace add redscaresu/swarm-dev && claude plugin install swarm-dev@swarm-dev
   ```

2. In your project's root, run `claude` once and accept "do you trust this folder?". Agents can't
   start in an untrusted folder.
3. Inside herdr, run `claude`, then `/swarm-dev:swarm` (type the whole name; the short form
   completes to another command). The first time, it sets up the board and asks once for your rules
   for builders: commit trailers, where credentials live, commands that must never run. Commit the
   `.claude/swarm/brief.md` it writes.
4. Run `/epic Add rate limiting to the API`, agree the epic, then run `/swarm-dev:swarm` again.
   Run it each time it stops for you.

Your agent can also answer "how do I use swarm-dev?" and "why did /swarm-dev:swarm stop?".

| Command | What it does |
|---|---|
| `/epic <title>` | Write a draft epic with a co-author agent; it is planned once you agree it. |
| `/swarm-dev:swarm` | Run everything after the design, stopping when a decision is yours. |
| `swarm.sh dash --watch` | The live dashboard above: what needs you, what is running, merges per day ([details](docs/dash.md)). |
| `swarm.sh status` | Agents that need a look, what waits on you, and what runs next. |

The other commands are tools the lead runs; they are listed in
[reference.md § Commands](docs/reference.md#commands). Settings go in `.claude/swarm/config`
([all settings](docs/method.md#configuring-a-project)).

## When `/swarm-dev:swarm` stops for you

| You see | Do |
|---|---|
| a draft epic | finish it with the co-author, then agree it |
| proposed epics or stories | approve them, or say what to change |
| a `lead` story | say go, and do its **You:** steps |
| a PR waiting for you | merge it, ask the lead to, or close it to send the story back |
| a `blocked` or `later` item | nothing, or set it `ready` / `active` to start it |
| a proposed rule (`lesson: <kind>`) | merge to adopt it, or close it |
| an agent's login expired | run `/login`, then tell `/swarm-dev:swarm` it's done |

## Cost and safety

Every agent is a full Claude Code session on your own logins. On infrafactory, from 2026-10-09 to
2026-10-16, a story's build averaged $5.75, and the whole swarm cost $1211.60 for 137 merged PRs
(about $9 each, planning and review included), at list prices from `swarm.sh flow` and `outcomes`.
The `cost` section of `swarm.sh flow` shows where your own tokens went, its `ci_health`
section shows how long CI takes per push, how often it goes red and how often it flakes, and its
`incidents` section counts, per day, the waits that timed out, the logins that expired and the
builders that stopped with no PR. Its `lead_queue` section shows, per day, the median and longest
time a held, escalated or ready-to-merge item waited on the lead, and names any still waiting. With
`merge = agent`, only a PR that costs money waits on you, so only those count.

Agents never touch real cloud or credentials: that work is a `lead` story, done in your session
while you watch. By default no agent merges. A story that fails twice is rebuilt once on Fable, the
most capable model, and then comes to the lead. Failed attempts clean up after themselves. The
details are in [reference.md](docs/reference.md#cleanup-escalation-and-session-logs).

## More

- [The method](docs/method.md): the short guide to how planning, building and merging work.
- [Reference](docs/reference.md): every rule, setting, command and log.
- On Foundry, Bedrock or Vertex, load your provider settings in `~/.zshrc` so herdr panes pick them
  up (an alias won't reach them):

  ```bash
  [[ -n "$HERDR_ENV" ]] && claude() { ( source ~/path/to/your-provider-env.sh && command claude "$@" ) }
  ```

- [Obsidian](https://obsidian.md) can show the board as a vault, grouped by status. It shows each
  file's committed status: what swarm.sh sets later (a review, an unblock) is kept in
  `.swarm/board-state` instead, so `git status` stays clean. `swarm.sh status` reads both.
- To update: `! claude plugin marketplace update swarm-dev`, then
  `! claude plugin update swarm-dev@swarm-dev`, and restart.
- [`SECURITY.md`](SECURITY.md) for security, [`AGENTS.md`](AGENTS.md) for working on swarm-dev itself.

## License

Apache-2.0.

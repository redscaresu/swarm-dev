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
  <img alt="How the swarm builds a design: /hld, /swarm-dev:swarm, /plan-hld, /plan-epic, the board, conductor, builders, review, merge" src="docs/assets/swarm-flow-light.png">
</picture>

1. You write a high-level design (HLD) with a co-author agent.
2. A planning swarm splits the design into epics, then each epic into stories of one PR
   each. Skeptic agents and codex try to break every plan before you see it, and you approve it.
3. A conductor agent takes an epic and starts one builder per story, each in its own git
   worktree and pane. With `goal` on, each builder also gets a Claude Code `/goal` made from its
   story's **Done when**, which keeps it working until that holds or a set number of turns pass.
   Each PR is reviewed by codex and `/code-review`, and the builder fixes what they find
   (with `goal` on, under a fresh goal that holds until the fixes are in). A codex review that
   runs past 10 minutes (`codex_minutes`) is stopped, and the PR says codex was skipped.
4. Green, reviewed PRs wait for you to merge. The next `/swarm-dev:swarm` starts the stories that were waiting on them.

Your own Claude session is the lead. It runs `/swarm-dev:swarm`, keeps an eye on the agents, and handles
`kind: lead` stories: real cloud, credentials and anything hard to undo. Your steps in those
stories are marked **You:**.

When reviews keep finding the same kind of problem across PRs, `/swarm-dev:swarm`
proposes a one-line rule for future builders, as a PR titled `lesson: <kind>`. You merge it
or close it.
Once a rule is in, each builder checks its diff against it before opening the PR and lists
what it checked under `Rules checked:` in the PR body. If that list is missing, the conductor
sends the PR back.

Everything is plain Markdown in `docs/` (the board), so a run can stop anywhere and the next
`/swarm-dev:swarm` picks up where it left off. The full method is in [`docs/method.md`](docs/method.md).

## Requirements

- [Claude Code](https://claude.com/claude-code) 2.1.145 or later, or 2.1.269 or later with `goal` on
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
3. Inside herdr, run `claude`, then `/swarm-dev:swarm`. Type the whole name: Claude Code
   completes the short form to `/swarm-dev:hld`. The first time, it offers to set up the board and
   asks once for your rules for builders (commit trailers, where credentials live, commands that must
   never run). Commit the `.claude/swarm/brief.md` it writes.
4. Run `/hld Add rate limiting to the API`, agree the design with the co-author, then run `/swarm-dev:swarm`
   again. Run it each time it stops for you.

Your agent can also answer "how do I use swarm-dev?" and "why did /swarm-dev:swarm stop?".

| Command | What it does |
|---|---|
| `/hld <title>` | Write a design with a co-author agent. |
| `/swarm-dev:swarm` | Run everything after the design, stopping when a decision is yours. |
| `swarm.sh status` | Show agents that need a look, what waits on you, and what runs next. |
| `swarm.sh dash --watch` | Open the live dashboard shown above, with how long each working agent has gone without a sign of life and how long each running codex review has run. With `lead = session` in the config, only your own steps say needs you; the rest goes in a lead's queue ([details](docs/dash.md)). |
| `swarm.sh wait --until-report conduct-<epic>` | Wait, with no timeout, until an epic's conductor writes its report, waits on a prompt, exits or needs a login. `/swarm-dev:swarm` runs it for you. |
| `swarm.sh cost [--since YYYY-MM-DD]` | Show where the tokens went, all time or since a date. |
| `swarm.sh outcomes` | One row per build: model, cost and tokens by type, review rounds and other tells, its epic, whether its PR and its story merged and when, findings fixed and declined by reviewer, when it started, why it was last closed, and its escalation steps. |

Settings such as `merge = agent` go in `.claude/swarm/config`
([all settings](docs/method.md#configuring-a-project)). On Foundry, Bedrock or Vertex, load your
provider settings in `~/.zshrc` so herdr panes pick them up. An alias won't reach them:

```bash
[[ -n "$HERDR_ENV" ]] && claude() { ( source ~/path/to/your-provider-env.sh && command claude "$@" ) }
```

## When `/swarm-dev:swarm` stops for you

| You see | Do |
|---|---|
| a draft design | finish it with the co-author, then agree it |
| proposed epics or stories | approve them, or say what to change |
| a `lead` story | say go, and do its **You:** steps |
| a builder stopped `cleared-on-error` (its goal was refused or failed) | nothing: the wave stops, the story is held on the board (`held_for:`, unless the close printed `not held:`), and the lead decides whether to build it again and tells you why |
| a PR waiting for you | merge it, or close it to send the story back |
| a `blocked` or `later` item | nothing, or set it `ready` / `active` to start it (`swarm.sh conduct` sets a `later` epic `active` itself) |
| a proposed rule (`lesson: <kind>`) | merge to adopt it, or close it |
| an agent's login expired | run `/login`, then tell `/swarm-dev:swarm` it's done |

## Cost and safety

Every agent is a full Claude Code session, on a model chosen by its role, and planning one epic
starts about ten agents. Agents use your own `claude`, `codex`, `gh` and `git` logins and never
touch real cloud or credentials. By default no agent merges.

When `swarm.sh close` closes the builder of a code, docs or chore story that is still `ready`, it
counts a failed build in the story's `attempts:` and clears the attempt away: its worktree, its
`story/<slug>` branch here and on origin, and any open PR, closed unmerged. `swarm.sh reconcile`
removes the same worktree and branches once a story's PR merges, closing its builder first if it is
open. When a PR closes unmerged, it removes them only if no builder is open. That leaves nothing to
clean up by hand, unless reconcile prints `build kept: <slug>` or `build cleared: <slug>`, which say
what is left. A story that has failed
twice is rebuilt on Fable, the most expensive model. This ships on as `escalate_after = 2` in `.claude/swarm/config`;
`escalate_after = 0` turns it off. If the Fable build fails as well, the story becomes a `lead`
story and the lead decides: it re-scopes the story and runs `swarm.sh reset <slug> <reason>` to build
it again (once per story), or drops it. Then it tells you what it chose and why. A Fable build
can stop to ask your consent to spend usage credits. The conductor accepts it for you, so a third
build can spend Fable usage credits. `swarm.sh dash` shows who is on call, how many builds
escalated today, which attempt each Fable builder is on, and each escalation step in the recent panel.

`swarm.sh close` keeps a copy of each closed agent's session log in `.swarm/sessions/`, because
Claude Code deletes them after 30 days. The copy is not redacted, so it can hold secrets the session
saw. Only your user can read it, and `.swarm/` is git-ignored, so it never leaves your machine.
`cost`, `outcomes` and `decisions` read the copy once the original is gone.

`/swarm-dev:swarm` tells you when a new version is out. To update, run
`! claude plugin marketplace update swarm-dev`, then `! claude plugin update swarm-dev@swarm-dev`,
and restart. See [`SECURITY.md`](SECURITY.md) for security and [`AGENTS.md`](AGENTS.md) for working
on swarm-dev itself.

## License

Apache-2.0.

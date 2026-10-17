---
name: swarm-dev
description: What swarm-dev is and how to drive it. Use when asked how to use swarm-dev, how to set up a project for it, or why /swarm-dev:swarm stopped and what to do next.
---

swarm-dev turns a design into merged PRs. The user writes a high-level design with a co-author
agent; agents split it into epics, then into one-PR stories, then build the stories in parallel.
Each agent runs in its own herdr pane where the user can watch it, and the user approves every
level before the next one starts.

All state lives in the board, the directory `swarm.sh config board_dir` prints.

## First run in a project

Work from the root of a git repo with a GitHub origin. `/hld`, `/swarm-dev:swarm` and the agents they start
run inside herdr (`HERDR_ENV=1`), as does `swarm.sh conduct`. `swarm.sh init`, `next`, `status`,
`config`, `cost`, `version` and `update` work outside herdr too.

1. `swarm.sh init` creates the board and `.claude/swarm/`. It never overwrites a file.
2. The user runs `claude` in that folder once and accepts the trust prompt. Only the user can do
   this; never accept it for them.
3. `/hld <title>` opens a co-author pane. The user writes the design there and agrees it.
4. `/swarm-dev:swarm` runs the rest. The first time, it asks the user once for the brief (commit trailers,
   where credentials live, commands that must never run).

## Why /swarm-dev:swarm stopped

It stops only when the user has to act: a draft design, epics or stories to approve, a `lead`
story, a PR to merge, an expired login (`/login`), a proposed rule, or a `blocked` or `later`
item (the user sets it `ready` or `active` to start it). After the user acts, run
`/swarm-dev:swarm` again. A story that failed on Fable (`next` says `escalated <slug>`) is not a
stop: the lead re-scopes it and runs `swarm.sh reset`, or runs `swarm.sh drop`, then tells the
user why. The full table of stops and what to do is in README § When `/swarm-dev:swarm` stops for you.

## Commands

| Command | Use |
|---|---|
| `/hld <title>` | write the design with a co-author |
| `/plan-hld <hld-file-name>` | split an agreed design (its file name in the board's `hld/`) into epics |
| `/plan-epic <epic>` | split an epic into stories |
| `/swarm-dev:swarm` | do the next step and loop until the user must decide |
| `swarm.sh next` | name the next step without doing it |
| `swarm.sh status` | agents that need a look, and what waits on the user |
| `swarm.sh dash --watch` | live dashboard: board, agents, recent events |
| `swarm.sh conduct <epic>` | start a conductor that builds one epic |
| `swarm.sh cost` | tokens and estimated cost per role |
| `swarm.sh reset <slug> <reason>` | put an escalated story back in the queue, with its kind and no attempts |
| `swarm.sh version` | the installed version, and whether a newer one is out |
| `swarm.sh update` | fetch the newest version (restart Claude Code after) |

## More detail

- `${CLAUDE_PLUGIN_ROOT}/README.md`: § Getting started and § When `/swarm-dev:swarm` stops for you.
- `${CLAUDE_PLUGIN_ROOT}/docs/method.md`: the method, who does what, and every setting (§ Configuring a project).
- `${CLAUDE_PLUGIN_ROOT}/docs/reference.md`: how each step works, and the rules behind each setting.

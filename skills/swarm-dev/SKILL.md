---
name: swarm-dev
description: What swarm-dev is (a Claude Code plugin that plans epics, splits them into one-PR stories and builds them in parallel herdr panes) and how to drive it. Use when asked to plan or build an epic with a swarm, how to use swarm-dev, how to set up a project for it, or why /swarm-dev:swarm stopped and what to do next.
---

swarm-dev turns an agreed design into merged PRs. The user agrees an HLD or an epic with a co-author
agent; agents split it into epics and one-PR stories, then build the stories in parallel, each in
its own herdr pane the user can watch. The user approves every level before the next one starts.
This text covers v0.30.0. All state lives in the board, the directory `swarm.sh config board_dir` prints.

## First run in a project

Work from the root of a git repo with a GitHub origin. The slash commands, `swarm.sh conduct` and
every agent run inside herdr (`HERDR_ENV=1`). `init`, `next`, `status`, `config`, `flow`, `dash`,
`outcomes`, `wait-pr`, `version` and `update` also work outside it.

1. `swarm.sh init` creates the board, `.claude/swarm/`, a CI workflow and a pre-commit hook, and
   names the `Bash(swarm.sh merge *)` allow rule if it is missing. It never overwrites a file.
2. The user runs `claude` in that folder once and accepts the trust prompt. Only the user can.
3. `/swarm-dev:hld <title>` (a design that becomes several epics) or `/epic <title>` (one epic)
   opens a co-author pane; the user writes the draft there and agrees it.
4. `/swarm-dev:swarm` runs the rest. The first time it asks once for the brief, which is then
   committed as `.claude/swarm/brief.md`.

## Why /swarm-dev:swarm stopped

It stops only when the user must act: a draft HLD or epic, plans to approve, a `lead` story, a PR
held for them (a protected path, money, or a merge of the base that dropped base lines), an expired
login, an agent waiting on a prompt, a proposed rule, a staged epic, or a `blocked` or `later` item.
Only the user agrees a draft; the lead sets a draft active itself only when it has a `parent:`, an
agreed HLD grants `epics`, or `lead_epics = on`. After the user acts, run `/swarm-dev:swarm` again.
An `escalated <slug>` story (failed on the top model, called impossible, or held) is the lead's: it
re-scopes it and runs `swarm.sh reset`, or `swarm.sh drop`, and tells the user why. README's
§ When `/swarm-dev:swarm` stops for you has the full table.

## While it builds

The lead keeps one `swarm.sh wait --lead` running and acts on each line it prints: `stuck:` (an idle
builder, 60 minutes by default), `conflict:`, `unmerged:`, `no-review:`, `main-red:`, `sign-blocked:`
and `idle:` each name their exit. From review round 3 the round cap sends back only regressions and
false statements; the rest is logged as deferred. Each time a person steps in, log it with
`swarm.sh intervene lead-hand|user-caught <cause> "<line>"`.

## Commands

| Command | Use |
|---|---|
| `/swarm-dev:hld <title>`, `/epic <title>` | write a draft HLD or epic with a co-author |
| `/plan-hld <hld>`, `/plan-epic <epic>` | split an HLD into epics, or an epic into stories |
| `/swarm-dev:swarm` | do the next step and loop until the user must decide |
| `swarm.sh next` / `status` | the next step / agents that need a look and what waits on the user |
| `swarm.sh wait --lead` | block until something needs the lead, then print it with its exit |
| `swarm.sh conduct <epic>` | start a conductor that builds one epic |
| `swarm.sh flow` | the project's numbers, one section per question (cost, start failures, holds, ...) |
| `swarm.sh reset <slug> <reason>` | requeue an escalated story, or lift a held one's hold |
| `swarm.sh version` / `update` | the installed version / fetch the newest (restart after) |

## More detail

- `${CLAUDE_PLUGIN_ROOT}/README.md`: § Getting started and § When `/swarm-dev:swarm` stops for you.
- `${CLAUDE_PLUGIN_ROOT}/docs/method.md`: the method, who does what, and every setting (§ Configuring a project).
- `${CLAUDE_PLUGIN_ROOT}/docs/reference*.md`: how each step works; `reference.md` lists which file holds each section.

# swarm-dev

[![CI](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml/badge.svg)](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/redscaresu/swarm-dev/badge)](https://scorecard.dev/viewer/?uri=github.com/redscaresu/swarm-dev)

Build software with a team of Claude Code agents you can watch. You write the design with one
agent; the rest plan it, argue with the plan, build it in parallel and merge it, each in its own
terminal pane. You step in only where a decision is yours.

You type two things:

```
/hld <title>    write the design with an agent
/swarm          do everything after that; after each decision of yours, run it
                again and it picks up where it left off
```

## How it works

```
  you ──▶ /hld <title>
          ┌──────────────────────────────────────────────┐
          │ HLD: co-written with you (Fable)             │
          │ a reviewer attacks the draft                 │
          └──────────────────────┬───────────────────────┘
                                 │  ◆ you agree the HLD
  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ ─ /swarm runs all below; resumes where it stopped
                                 ▼
          ┌──────────────────────────────────────────────┐
          │ /plan-hld: surveys → lead → skeptics         │
          │            + codex + critic                  │
          └──────────────────────┬───────────────────────┘
                                 │  ◆ you approve the epics
                                 ▼
          ┌──────────────────────────────────────────────┐
          │ /plan-epic (each epic): surveys → lead       │
          │            → skeptic per story + codex       │
          │            + critic                          │
          └──────────────────────┬───────────────────────┘
                                 │  ◆ you approve the stories
                                 ▼
          ┌──────────────────────────────────────────────┐
          │ conductor (one per epic, a fresh session)    │
          │  ├─ story A ─ builder, own worktree ─▶ PR    │
          │  ├─ story B ─ builder, own worktree ─▶ PR    │
          │  └─ story C ─ builder, own worktree ─▶ PR    │
          │ each PR: codex review, CI green, then merge  │
          └──────────────────────┬───────────────────────┘
                                 │  epic done
                                 ▼
                        next epic, or ◆ you: operator stories,
                        lead-run steps, what to start next

  ◆ = the loop stops for you      every agent runs in its own herdr pane:
                                  a workspace per HLD, a tab per story
```

**Words used here**

- **HLD** (high-level design): one document saying what you are building and why. Everything else
  comes from it.
- **Epic**: a goal bigger than one pull request, with a **Done when** that could fail.
- **Story**: one pull request's worth of work. Its `kind` says who does it: an agent (`code`,
  `docs`, `chore`, `verify`), you (`operator`), or your own session because it touches real cloud
  or credentials (`lead`).
- **Board**: those files in `docs/hld/`, `docs/epics/` and `docs/stories/`, viewed in Obsidian.
- **Conductor**: a fresh agent that builds one epic's stories and merges them.
- **Pane**: a terminal in [herdr](https://herdr.dev). Every agent gets one, so you can watch any of
  them at any time.

## Why this way

- **You can see every agent.** Each one runs in its own pane: a herdr workspace per HLD, a tab per
  story. Nothing works out of sight.
- **Plans are attacked before anything is built.** Each story faces a skeptic that tries to refute
  it, and the whole plan faces a critic and codex, a model from another company that shares fewer
  blind spots. You see what they found before you approve.
- **The right model for each job.** The most capable model for the design, Opus for judgment and
  code, Sonnet for reading and running tests. The table is in [`docs/method.md`](docs/method.md).
- **Nothing is lost when you stop.** The plan lives in files in git, not in a chat, so `/swarm`
  always knows where things stand.

## Quick start

### 1. Install the prerequisites

| Tool | What it is for | Check it works |
|---|---|---|
| [Claude Code](https://claude.com/claude-code) | runs every agent | `claude --version` |
| [herdr](https://herdr.dev) | the panes every agent runs in | `herdr --version` |
| [GitHub CLI](https://cli.github.com), logged in | pull requests, checks, merges | `gh auth status` |
| [codex CLI](https://github.com/openai/codex), logged in | the second-opinion review | `codex --version` |
| [Obsidian](https://obsidian.md) 1.9 or later | seeing the board | Settings → About |
| `git`, `python3`, `bash` | the script itself | `git --version && python3 --version` |

Your project must be a git repository with its `origin` on GitHub.

### 2. Install the plugin

```bash
claude plugin marketplace add redscaresu/swarm-dev
claude plugin install swarm-dev@swarm-dev
```

Then restart Claude Code, so the commands and `swarm.sh` are loaded.

### 3. Set up your project

From your project's root:

```bash
git clone --depth 1 https://github.com/redscaresu/swarm-dev /tmp/swarm-dev
mkdir -p docs .claude/swarm
cp -Rn /tmp/swarm-dev/templates/docs/. docs/
grep -qx '.swarm/' .gitignore || echo '.swarm/' >> .gitignore
grep -qx 'docs/.obsidian/\*' .gitignore || printf '%s\n' 'docs/.obsidian/*' '!docs/.obsidian/app.json' >> .gitignore
```

This adds the board's formats and Obsidian views to `docs/`, and keeps the agents' working files
(`.swarm/`) and your personal Obsidian layout out of git.

Then write `.claude/swarm/brief.md`: the rules every building agent gets for your project. For
example:

```markdown
Never read ~/.aws or any .env file. Never run `make deploy`.
End commit messages with "Co-Authored-By: Claude <noreply@anthropic.com>".
Run `make test` before opening a pull request.
```

Commit it (if `.claude/` is in your `.gitignore`, add `!.claude/swarm/`). Finally, list your shared
files in `AGENTS.md` (root config, schemas, CI scripts) so no two agents edit them at once.

### 4. Open the board in Obsidian

In Obsidian, choose **Open folder as vault** and pick your project's `docs/` folder. Open
`Board.base`: its views show stories by status and by epic, the epics, **Waiting on you** (your
`operator` stories) and **Lead-run** (steps your own session runs). `hld/HLDs.base` lists the
designs. If the views do not render, turn on **Bases** under Settings → Core plugins.

### 5. Write your first HLD

Open herdr in your project, start `claude` in a pane, and run:

```
/hld Add rate limiting to the API
```

1. A new pane opens with a co-author. **Talk to it there**: it reads your code, asks you the
   questions that decide the design, and writes your answers into
   `docs/hld/YYYY-MM-DD-add-rate-limiting-to-the-api.md`.
2. When the draft says what you mean, **go back to your first pane and say it is ready**. A
   reviewer attacks it; fix what it finds, with the co-author.
3. **Tell your first pane the HLD is agreed.** It marks it agreed and opens a pull request for it.

Stopped halfway? Run `/hld` on its own and it carries on with the draft in progress. The full
walkthrough, and what makes a good HLD: [`docs/method.md` § Writing the HLD](docs/method.md#writing-the-hld).

### 6. Run the rest

```
/swarm
```

It plans the epics, scopes each into stories, and hands each epic to a conductor, which opens a
herdr workspace named after your HLD with one tab per story. Watch any pane, or the board in
Obsidian. `/swarm` stops whenever a decision is yours; make it, then run `/swarm` again.

## When `/swarm` stops for you

| It shows you | What to do |
|---|---|
| a draft HLD | finish it with the co-author, then say it is ready, then agreed |
| proposed epics or stories, with what the skeptics found | approve them, or say what to change |
| an `operator` story | do what its **Done when** says (a decision or a step by hand) |
| a `lead` story | it touches real cloud or credentials: tell your session to run it |
| a `blocked` story | nothing, usually: it clears itself when what it waits on merges |
| a `later` story or epic | set it `ready` (a story) or `active` (an epic) when you want it started |

`swarm.sh next` shows what `/swarm` would do next, without doing it.

## Cost

Every agent is a full Claude Code session, so a swarm uses far more tokens than one chat. Scoping
one epic starts about ten agents; each story gets one builder. To keep it down, each epic gets a
fresh conductor instead of one long session that grows, and cheaper models do the reading and
running. On a subscription this counts against your plan's limits.

## Safety

Agents act with your own `claude`, `codex`, `gh` and `git` logins. Builders work in separate git
worktrees and never merge: a conductor (or your session, for a one-off story) merges, and only
when every check is green. No agent is given a story that needs real cloud, credentials or your
judgment. [`SECURITY.md`](SECURITY.md) has the details and how to report a vulnerability.

## For agents, and contributing

Agents: read [`AGENTS.md`](AGENTS.md), which says how to check the setup, run the chain, and the
rules that are not negotiable. To work on swarm-dev itself, see its § Working on this repository.

## License

Apache-2.0.

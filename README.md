# swarm-dev

[![CI](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml/badge.svg)](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/redscaresu/swarm-dev/badge)](https://scorecard.dev/viewer/?uri=github.com/redscaresu/swarm-dev)

A way of building software with a swarm of Claude Code agents that you can watch: a high-level
design (HLD) is written with you, split into epics, each epic scoped into one-PR stories that
skeptics and a second model family try to refute, and the surviving stories are built in
parallel, each agent in its own herdr pane.

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

```
/hld <title>            co-write the HLD with the most capable model; a reviewer attacks it
/swarm                  run everything after that, resuming wherever it stopped
```

`/swarm` does these for you, one at a time, and stops where you must decide:

```
/plan-hld <hld>         split the agreed HLD into epics (a swarm; you approve)
/plan-epic <epic>       scope an epic into stories (a swarm; you approve)
swarm.sh conduct <epic> a fresh conductor builds and merges the epic's stories
```

How and why it works: [`docs/method.md`](docs/method.md).

## What is different

- **Every agent is visible.** Each runs in its own herdr pane: a workspace per HLD, a tab per
  story. Nothing runs as a hidden subagent.
- **Stories are attacked before they are built.** Every story faces a skeptic, and the whole plan
  faces codex (a different model family) and a critic, before you approve it.
- **Model and effort follow the role**, in one table (`policy()` in `bin/swarm.sh`): the most
  capable model for design, Opus for judgment and code, Sonnet for reading and running.
- **The board is files in git.** One file per HLD, epic and story, with front matter; no shared
  board file, and decisions that are yours are `kind: operator` stories on it.

## Quick start

### 1. Prerequisites

| Tool | Why | Check |
|---|---|---|
| [Claude Code](https://claude.com/claude-code) | runs every agent | `claude --version` |
| [herdr](https://herdr.dev) | the panes every agent runs in | `herdr --version` |
| [GitHub CLI](https://cli.github.com), logged in | PRs, checks, merges | `gh auth status` |
| [codex CLI](https://github.com/openai/codex), logged in | the cross-model review | `codex --version` |
| `git`, `python3`, `bash` | the script itself | `git --version && python3 --version` |
| [Obsidian](https://obsidian.md) 1.9 or later | the board: stories, epics and HLDs as tables | Settings → About |

The project must be a git repository with a GitHub `origin`.

### 2. Install the plugin

```bash
claude plugin marketplace add redscaresu/swarm-dev
claude plugin install swarm-dev@swarm-dev
```

Restart Claude Code afterwards: `swarm.sh` is put on the Bash tool's `PATH` when a session starts.
The commands arrive as `/hld`, `/plan-hld` and `/plan-epic` (also `/swarm-dev:<name>`).

### 3. Set up your project

From the project's root:

```bash
git clone --depth 1 https://github.com/redscaresu/swarm-dev /tmp/swarm-dev
mkdir -p docs .claude/swarm
cp -Rn /tmp/swarm-dev/templates/docs/. docs/     # board formats, Obsidian views and link settings
grep -qx '.swarm/' .gitignore || echo '.swarm/' >> .gitignore
grep -qx 'docs/.obsidian/\*' .gitignore || printf '%s\n' 'docs/.obsidian/*' '!docs/.obsidian/app.json' >> .gitignore
$EDITOR .claude/swarm/brief.md                   # your rules for every builder (see below)
```

`.claude/swarm/brief.md` is appended to every builder's brief. Put there what is specific to your
project: commit and PR trailers, where credentials live and must not be read, commands that must
not run. Commit it (if `.claude/` is gitignored, add `!.claude/swarm/`). Then name your shared
files in `AGENTS.md` (root config, schemas, CI scripts), so no two stories in one wave edit them.

### The board in Obsidian

The board is plain files in `docs/`; Obsidian is how you see it: what is ready, what is blocked,
and what waits on you.

1. In Obsidian, **Open folder as vault** and pick the project's `docs/` folder.
2. Check that **Bases** is on under Settings → Core plugins (it is by default).
3. Open `Board.base`. Its views: **Board** (stories by status), **By epic**, **Epics**,
   **Waiting on you** (`operator` stories) and **Lead-run** (`lead` stories).
   `hld/HLDs.base` lists the HLDs by status.

`docs/.obsidian/app.json` is the one Obsidian file to commit: it makes Obsidian write standard
relative markdown links, never `[[wikilinks]]`, so links work on GitHub and a link checker can
follow them. The rest of `.obsidian/` is per-user UI state, kept out of git by the `.gitignore`
lines above. Do not use spaces in file names: Obsidian writes them as `%20` in links.

### 4. Run it

Open herdr in the project, start `claude` in a pane, and start the first design:

```
/hld Add rate limiting to the API    # co-write the design in a new pane; say when it is ready
```

From then on, one command runs the whole chain and picks up wherever it stopped:

```
/swarm
```

It reads the board, does the next step (plan the epics, scope an epic into stories, hand an epic
to a conductor, build a one-off story) and loops. It stops only where you must decide: agreeing
an HLD, approving epics or stories, an `operator` story, or a `later` epic to start. Answer, then
run `/swarm` again. `swarm.sh next` shows the next step without doing it.

Each conductor runs in a herdr workspace named after the HLD, with its own tab and one tab per
story. The individual commands (`/plan-hld`, `/plan-epic`, `swarm.sh conduct <epic>`) still work
on their own.

## For agents

Read [`AGENTS.md`](AGENTS.md): how to set a project up, run the chain, and the rules that are not
negotiable.

## Security

Agents run with your local `claude`, `codex`, `gh` and `git` authentication; what they may and may
not do is in [`SECURITY.md`](SECURITY.md), which is also where to report a vulnerability. CI runs
shellcheck, gitleaks, zizmor on the workflows and OpenSSF Scorecard; every action is pinned to a
commit SHA. Secrets are stopped at three layers: `make hooks` installs a gitleaks pre-commit hook,
the CI gitleaks job scans the full history and is a required check on `main`, and GitHub secret
scanning with push protection is on.

## License

Apache-2.0.

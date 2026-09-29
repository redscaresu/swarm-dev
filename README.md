# swarm-dev

[![CI](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml/badge.svg)](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/redscaresu/swarm-dev/badge)](https://scorecard.dev/viewer/?uri=github.com/redscaresu/swarm-dev)

A way of building software with a swarm of Claude Code agents that you can watch: a high-level
design (HLD) is written with you, split into epics, each epic scoped into one-PR stories that
skeptics and a second model family try to refute, and the surviving stories are built in
parallel, each agent in its own herdr pane.

```
/hld <title>            co-write the HLD with the most capable model; a reviewer attacks it
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
cp -Rn /tmp/swarm-dev/templates/docs/. docs/     # HLD, epic and story formats, and the board views
grep -qx '.swarm/' .gitignore || echo '.swarm/' >> .gitignore
$EDITOR .claude/swarm/brief.md                   # your rules for every builder (see below)
```

`.claude/swarm/brief.md` is appended to every builder's brief. Put there what is specific to your
project: commit and PR trailers, where credentials live and must not be read, commands that must
not run. Commit it (if `.claude/` is gitignored, add `!.claude/swarm/`). Then name your shared
files in `AGENTS.md` (root config, schemas, CI scripts), so no two stories in one wave edit them.
The `.base` files are optional [Obsidian](https://obsidian.md) views of the board.

### 4. Run it

Open herdr in the project, start `claude` in a pane, and:

```
/hld Add rate limiting to the API    # co-write the design in a new pane; say when it is ready
/plan-hld 2026-09-29-add-rate-limiting-to-the-api
/plan-epic <epic-slug>               # you approve the stories before any file is written
```

Then build an epic from a Claude session in herdr: ask it to run `swarm.sh conduct <epic-slug>`.
A new herdr workspace named after the HLD appears, with the conductor's tab and one tab per story.

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

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

## Requirements

[Claude Code](https://claude.com/claude-code), [herdr](https://herdr.dev), `gh` (authenticated),
`git`, `python3`, and the [codex CLI](https://github.com/openai/codex) for the cross-model check.

## Install

```bash
claude plugin marketplace add redscaresu/swarm-dev
claude plugin install swarm-dev@swarm-dev
```

The commands arrive as `/hld`, `/plan-hld` and `/plan-epic` (also `/swarm-dev:<name>`), and
`swarm.sh` is on the Bash tool's `PATH` while the plugin is enabled.

## Set up a project

1. Copy `templates/docs/` into the project's `docs/`: the READMEs define the HLD, epic and story
   formats, and the `.base` files are Obsidian views of the board (optional).
2. Add `.swarm/` to `.gitignore`; it holds pane records, briefs and agent outputs.
3. Write `.claude/swarm/brief.md`: the project's rules every builder gets after the standard ones
   (commit trailers, where credentials live and must not be read, ADR conventions).
4. Say in `AGENTS.md` which files are shared, so no two stories in one wave edit them.

Then start with `/hld <title>` inside herdr.

## Security

Agents run with your local `claude`, `codex`, `gh` and `git` authentication; what they may and may
not do is in [`SECURITY.md`](SECURITY.md), which is also where to report a vulnerability. CI runs
shellcheck, gitleaks, zizmor on the workflows and OpenSSF Scorecard; every action is pinned to a
commit SHA. Secrets are stopped at three layers: `make hooks` installs a gitleaks pre-commit hook,
the CI gitleaks job scans the full history and is a required check on `main`, and GitHub secret
scanning with push protection is on.

## License

Apache-2.0.

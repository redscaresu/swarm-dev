# AGENTS.md

You are an agent. This file tells you how to use swarm-dev in a project, and how to work on this
repository. The method, and why it is shaped this way, is in [`docs/method.md`](docs/method.md):
read it before you run anything.

## Using swarm-dev in a project

**Check before you start.** Stop and tell the user which is missing if any of these fail:

```bash
[ "$HERDR_ENV" = 1 ]            # you are inside a herdr pane; every agent opens a pane beside you
command -v swarm.sh             # the plugin is installed and this session started after it
gh auth status                  # PRs, checks and merges go through gh
git remote get-url origin       # a GitHub origin; swarm.sh resolves the owner from it
```

A read-only review (codex, /code-review, a skeptic) skips these checks: it reads a diff and needs
none of them, and `gh auth status` fails inside codex's sandbox.

If `swarm.sh` stops with "Claude Code does not trust <folder> yet", ask the user to run `claude` in
that folder once and accept the trust prompt. Never accept it for them, and never edit
`~/.claude.json`.

If `swarm.sh` is missing, the user runs `claude plugin marketplace add redscaresu/swarm-dev` and
`claude plugin install swarm-dev@swarm-dev`, then restarts Claude Code.

**Set the project up** if `stories/README.md` does not exist in the board (`swarm.sh config board_dir`): follow the README's
§ Quick start, step 3 (it includes the Obsidian link settings; keep links as markdown links,
never `[[wikilinks]]`). Ask the user for the contents of `.claude/swarm/brief.md` (their commit
trailers, where credentials live, commands that must not run); do not invent them.

**Run the chain with `/swarm`.** It reads the board with `swarm.sh next`, does the next step, and
loops until the user must decide; run it again after they do. The steps it takes, which you can
also run one by one, and which each wait for the user's approval:

| Step | You run | It produces |
|---|---|---|
| Design | `/hld <title>` | `docs/hld/YYYY-MM-DD-<slug>.md`, co-written in its own pane |
| Epics | `/plan-hld <hld-file-name>` | `docs/epics/<slug>.md` per epic, after approval |
| Stories | `/plan-epic <epic-slug>` | `docs/stories/<slug>.md` per story, after approval |
| Build | `swarm.sh conduct <epic-slug>` or `conduct --backlog` | a fresh conductor that builds the epic (or the ready stories with no epic), starts a review agent per green PR, and merges only with `merge = agent` |

Useful while it runs:

- `swarm.sh status [--all]`: agents that need a look (including empty panes where a start failed), stacked builds whose parent moved or merged, and what waits on the user; `--all` lists idle agents and blocked stories too.
- `swarm.sh dash [--watch [seconds]]`, and `swarm.sh dash --project <dir>` (repeatable): the board, agents, running-now box, merges-per-day speedometer, model ladder and recent events on one read-only screen; each `--project` draws another project.
- `swarm.sh tidy [--yes]`: close empty panes and retired agents' panes; lists them first.
- `swarm.sh next`: the next step, without doing it. It prints `release` when `main` has changes since the last `v<version>` tag.
- `swarm.sh conduct <epic>|--backlog`: a fresh conductor for one epic, or for the ready stories with no epic; `swarm.sh watch [--backlog]` returns when a story PR needs the lead.
- `swarm.sh wait --lead`: returns when the lead's queue gains a held or escalated story or a green PR that waits on the user.
- `swarm.sh review-agent <slug> <pr-url>`: a read-only review agent for one PR, scoped to its story's `touches` and **Done when**.
- `swarm.sh cost [--since YYYY-MM-DD]`, `swarm.sh outcomes`, `swarm.sh flow`, `swarm.sh features`: tokens and cost per role (with a row for the lead's own sessions), one row per build with its timings, throughput, and whether each feature in `docs/features.tsv` earns its keep.
- `swarm.sh policy <role>`: model and effort for a role.
- `swarm.sh tell <slug> <kind> <file>`: findings, nudge or resume sends an idle builder a file; note leaves a conductor a note, busy or not.
- `swarm.sh merge [--board|--release] <pr-url>`: merge a green PR in review with its head pinned, wait for CI on main, then reconcile; `--release` merges the lead's version-bump PR.
- `swarm.sh log-finding [--declined <reason>] [--reviewer <who>] <kind> <pr> <text>` and `swarm.sh lessons [--all]`: the outer loop. Log findings by kind, with the reason for a declined one and who raised it (codex, code-review, ci, conductor, lead, skeptic, critic, or escaped); list kinds recurring in 3+ PRs with no brief rule yet.
- `herdr agent read <name> --source recent-unwrapped`: what an agent is doing.

**Rules that are not negotiable:**

- You supervise; the agents do the work. Do not write an HLD, epic or story plan yourself when a
  command exists for it. The exception is a small epic (three stories or fewer, none `risk: high`),
  which `/plan-epic` has the lead plan alone.
- Never merge a PR whose checks are not all green on its head commit. With `merge = human` (the
  default), never merge at all: `swarm.sh review <slug> <PR URL>` hands it to the user.
- Never hand a `kind: lead` story (real cloud, credentials, or a step that is the user's) to an
  agent. List them for the user.
- One conductor per epic. Two epics run side by side only when their stories touch different files;
  otherwise one story `depends_on` the other. Only the lead edits the shared files `AGENTS.md` names.
- A question for the user is a `kind: lead` story with a **You:** step, not a line in chat.

## Working on this repository

```
bin/swarm.sh          the only script: panes, story builds, conductors, the model policy
commands/             /hld, /plan-hld, /plan-epic, /swarm (Markdown the plugin loads)
tests/                *_test.sh: next against throwaway boards, cost against a log fixture
docs/method.md        the method; change it when behaviour changes
templates/docs/       what a project copies: the board formats and Obsidian views
.claude-plugin/       plugin and marketplace manifests
```

Before you open a PR:

```bash
make hooks                                  # once: the gitleaks pre-commit hook
shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh
for t in tests/*_test.sh; do bash "$t"; done
claude plugin validate .
```

A PR that changes what a user runs, sees or has to do updates README.md in the same PR. Before
the PR opens, run the humanizer skill (`humanizer:humanizer`) over the prose it changes for people to
read: README.md, docs/, HLDs, the text in commands/ that the user sees, and the PR description. Say
in the PR that you did. Story files and briefs are written for agents and need no pass.

Secrets are stopped at three layers: the pre-commit hook, the CI gitleaks job over the full
history (required on `main`), and GitHub push protection. Keep template links as markdown links,
never `[[wikilinks]]`.

`bin/swarm.sh` must run on macOS's bash 3.2: no `mapfile`, no associative arrays. Pin every GitHub
Action to a commit SHA, with `persist-credentials: false` and read-only permissions; zizmor fails
the PR otherwise. CI (shellcheck, test, plugin-validate, gitleaks, zizmor) is required on `main`.
When `swarm.sh next` prints `release` (`main` has changes since the last `v<version>` tag), the lead cuts a
release through `/swarm-dev:swarm`'s release arm and `swarm.sh merge --release`: a PR that bumps `version` in
`.claude-plugin/plugin.json` and nothing else. `claude plugin update` fetches nothing while the version is
unchanged. No story PR bumps it, and a story PR without a bump is not a review finding. Merging a version
bump to `main` publishes the release and its `v<version>` tag (`.github/workflows/release.yml`); a merge
without one publishes nothing.

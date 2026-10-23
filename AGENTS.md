# AGENTS.md

swarm-dev is a Claude Code plugin that turns an agreed epic into merged PRs. Agents split the epic
into one-PR stories and build them in parallel, each in its own herdr pane and git worktree.

Check these first. If any fails, stop and tell the user which one:

```bash
[ "$HERDR_ENV" = 1 ]            # you are inside a herdr pane; every agent opens a pane beside you
command -v swarm.sh             # the plugin is installed and this session started after it
gh auth status                  # PRs, checks and merges go through gh
git remote get-url origin       # a GitHub origin; swarm.sh resolves the owner from it
```

Then run these three, in order:

1. `swarm.sh init`, from the project's git root. It leaves the board (`docs/epics/`,
   `docs/stories/`), `.claude/swarm/` with a config, the `.gitignore` lines, a CI workflow and a
   pre-commit hook that run `make check`. With no `check` target in the Makefile, init says so;
   add one, or CI fails every change that is not board-only.
2. `/epic <title>` (the plugin's full name is `/swarm-dev:epic`). It leaves `docs/epics/<slug>.md`,
   written with the user in its own pane. It stays `status: draft` until the user agrees it, then
   becomes `active`.
3. `/swarm-dev:swarm`. It reads the board with `swarm.sh next`, plans the epic into stories,
   builds them and loops until the user must decide. It leaves `docs/stories/<slug>.md` files and
   one PR per story. With the default `merge = human` the user merges each PR; with
   `merge = agent` the swarm merges them. Run it again after each decision.

The method, and why it is shaped this way, is in [`docs/method.md`](docs/method.md). Read it before
you run anything. [`llms.txt`](llms.txt) maps the rest of the docs.

## Using swarm-dev in a project

A read-only review (codex, /code-review, a skeptic) skips the four checks above: it reads a diff
and needs none of them, and `gh auth status` fails inside codex's sandbox.

If `swarm.sh` stops with "Claude Code does not trust <folder> yet", ask the user to run `claude` in
that folder once and accept the trust prompt. Never accept it for them, and never edit
`~/.claude.json`.

If `swarm.sh` is missing, the user runs `claude plugin marketplace add redscaresu/swarm-dev` and
`claude plugin install swarm-dev@swarm-dev`, then restarts Claude Code.

**Set the project up** if `<board>/stories/README.md` does not exist, where `<board>` is what
`swarm.sh config board_dir` prints (`docs` by default, so `docs/stories/README.md`): run `swarm.sh init` and follow the root README.md's § Getting started from step 3. Keep links as
markdown links, never `[[wikilinks]]`. Ask the user for the contents of `.claude/swarm/brief.md`
(their commit trailers, where credentials live, commands that must not run); do not invent them.

**Run the chain with `/swarm-dev:swarm`.** It reads the board with `swarm.sh next`, does the next step, and
loops until the user must decide; run it again after they do. The steps it takes, which you can
also run one by one, and which each wait for the user's approval:

| Step | You run | It produces |
|---|---|---|
| Epic | `/epic <title>` | `docs/epics/<slug>.md`, a draft co-written in its own pane and attacked by a reviewer; `active` once the user agrees it |
| Stories | `/plan-epic <epic-slug>` | `docs/stories/<slug>.md` per story, after approval; a large epic is split into child epics first |
| Build | `swarm.sh conduct <epic-slug>` or `conduct --backlog` | a fresh conductor that builds the epic (or the ready stories with no epic), starts a review agent per green PR, and merges only with `merge = agent` |

Useful while it runs:

- `swarm.sh status [--all]`: agents that need a look (including empty panes where a start failed), stacked builds whose parent moved or merged, and what waits on the user; `--all` lists idle agents and blocked stories too.
- `swarm.sh dash [--watch [seconds]]`, and `swarm.sh dash --project <dir>` (repeatable): the board, agents, running-now box, merges-per-day speedometer, model ladder and recent events on one read-only screen; each `--project` draws another project.
- `swarm.sh tidy [--yes]`: close empty panes and retired agents' panes; lists them first.
- `swarm.sh next`: the next step, without doing it. It prints `release` when `main` has changes since the last `v<version>` tag, and `idle:` lines for capacity nothing uses (`dash` shows them too).
- `swarm.sh conduct <epic>|--backlog`: a fresh conductor for one epic, or for the ready stories with no epic; `swarm.sh watch [--epic <slug>|--backlog] [repo...]` returns when a story PR needs the lead.
- `swarm.sh wait --lead`: returns when the lead's queue gains a held or escalated story or a green PR that waits on the user.
- `swarm.sh wait-pr <pr-url>`: wait for a PR's checks; exit 0 green, 1 red, 2 on a gh error, a conflict with the base, or the timeout. Every CI wait goes through it; the guard refuses a hand-written `gh pr checks` loop.
- `swarm.sh review-agent <slug> <pr-url>`: a read-only review agent for one PR, scoped to its story's `touches` and **Done when**.
- `swarm.sh outcomes` and `swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>]`: one row per build with its timings, and the project's numbers a section each: `cost`, `features`, `reviewers`, `throughput`, `time_in_state` (with time held ready while a conductor ran, and how long a ready story waited for its build) and more.
- `swarm.sh dataset`: write `.swarm/dataset.jsonl`, one JSON line per merged story, its plan beside what the build took.
- `swarm.sh policy <role>`: model and effort for a role.
- `swarm.sh tell <slug> <kind> <file>`: findings, nudge or resume sends an idle builder a file; `tell conduct-<epic> note <file>` appends it to a conductor's inbox, busy or not.
- `swarm.sh merge [--board|--release] <pr-url>`: merge a green PR in review with its head pinned, wait for CI on main, then reconcile; `--release` merges the lead's version-bump PR. After a `--board` merge it pulls the board and sends each running conductor a note naming the stories that merge made ready. Where the base has a merge queue it enqueues the PR. When CI on main goes red on a commit it merged, it prints `fix-main:` and writes a `fix-main-<sha>` story, which `next` names first. With `merge_admin = on` it passes `--admin` once its own checks pass. In a swarm project the plugin's guard hook refuses any other merge.
- `swarm.sh step-up <slug> <trigger>`: hand a struggling build to the next model in `escalate_ladder` (off by default), on the same branch, without counting an attempt. With the ladder set, swarm.sh runs it itself on `no-pr`, `stalled`, `findings-3` and `ci-red-2`. `step-up --resume <slug>` starts a rung whose start failed.
- `swarm.sh intervene lead-hand|user-caught "<one line>"`: log a time a person had to step in; `flow` and `dash` count them.
- `swarm.sh dash --check`: compare each figure dash shows with the command that owns it.
- `swarm.sh log-finding [--declined <reason> | --filed] [--reviewer <who>] <kind> <pr> <text>`: the outer loop. Log findings by kind, with the reason for a declined one and who raised it (codex, fallback, code-review, ci, conductor, lead, skeptic, critic, split-critic, or escaped). `outcomes`' recurring block lists kinds fixed on 3+ PRs, and `/swarm-dev:swarm` files a `checks:` story for each.
- `herdr agent read <name> --source recent-unwrapped`: what an agent is doing.

**Rules that are not negotiable:**

- You supervise; the agents do the work. Do not write an epic or story plan yourself when a
  command exists for it. The exception is a small epic (three stories or fewer, none `risk: high`),
  which `/plan-epic` has the lead plan alone.
- Never merge a PR whose checks are not all green on its head commit. With `merge = human` (the
  default), never merge at all: `swarm.sh review <slug> <PR URL>` hands it to the user.
- Agents start with an allowlisted environment. A token you exported reaches a builder only when
  its story names it under `env:`.
- The plugin's guard hook refuses a raw merge, a `cd <dir>` followed by `;` (write
  `cd <dir> || exit 1 &&`), a `git checkout` that drops uncommitted changes, and, for an agent,
  `git checkout`, `switch`, `restore`, `reset --hard`, `stash` or `clean` in the main checkout,
  `pkill`, `killall` and `gh pr checks` loops (reference.md § Merging).
- Never hand a `kind: lead` story (real cloud, credentials, or a step that is the user's) to an
  agent. List them for the user.
- One conductor per epic. Two stories clash only when their `touches` name the same `file:symbol`,
  or either names the bare file; clashing stories in two epics get a `depends_on`. Only the lead
  edits the shared files the project's `AGENTS.md` names.
- A question for the user is a `kind: lead` story with a **You:** step, not a line in chat.

## Working on this repository

```
bin/swarm.sh          the entry point: usage, settings, the model policy, the command dispatch
bin/lib/*.sh          the commands by group (agents, board, build, dash, lifecycle, merge, reports)
bin/lib/*.py          the Python helpers the commands run
commands/             /epic, /plan-epic, /swarm (Markdown the plugin loads)
hooks/                hooks.json; merge-guard.sh (the guard on merges and commands that lose work), agent-state.sh
                      (an agent's state for herdr) and lead-stop.sh (the lead's turn ends only when next allows)
scripts/              test.sh (the make test runner), pre-commit, board-only.sh
tests/                *_test.sh, run by make test; doc_check_test.sh checks the docs name only what swarm.sh has
docs/method.md        the method; change it when behaviour changes
docs/reference.md     every rule, setting, command and log
board/                this repo's own board (board_dir = board); docs/ holds user docs only
skills/swarm-dev/     the plugin skill that answers "how do I use swarm-dev?"
templates/docs/       what a project copies: the board formats and Obsidian views
.claude-plugin/       plugin and marketplace manifests
```

Before you open a PR:

```bash
make hooks                                  # once: the gitleaks pre-commit hook
shellcheck bin/swarm.sh bin/lib/*.sh scripts/pre-commit scripts/demo-dash.sh scripts/board-only.sh scripts/test.sh tests/*.sh
python3 -m py_compile bin/lib/*.py
make test                                   # every tests/*_test.sh: in parallel, SLOW files first, SERIAL ones alone
                                            # a file past TEST_FILE_TIMEOUT (600 s, 3x for SLOW) is killed and fails as TIMEOUT
claude plugin validate .
```

A PR that changes what a user runs, sees or has to do updates README.md in the same PR. Before
the PR opens, run the humanizer skill (`humanizer:humanizer`) over the prose it changes for people to
read: README.md, docs/, epics, the text in commands/ that the user sees, and the PR description. Say
in the PR that you did. Story files and briefs are written for agents and need no pass.

Secrets are stopped at three layers: the pre-commit hook, the CI gitleaks job over the full
history (required on `main`), and GitHub push protection. Keep template links as markdown links,
never `[[wikilinks]]`.

`bin/swarm.sh` and `bin/lib/*.sh` must run on macOS's bash 3.2: no `mapfile`, no associative arrays. Pin every GitHub
Action to a commit SHA, with `persist-credentials: false` and read-only permissions; zizmor fails
the PR otherwise. CI (shellcheck, test, plugin-validate, gitleaks, zizmor) is required on `main`; `test` passes when its 8 `test-shard` jobs do (`SHARD=i/N` runs one locally).
When `swarm.sh next` prints `release` (`main` has changes since the last `v<version>` tag), the lead cuts a
release through `/swarm-dev:swarm`'s release arm and `swarm.sh merge --release`: a PR that bumps `version` in
`.claude-plugin/plugin.json` and nothing else. `claude plugin update` fetches nothing while the version is
unchanged. No story PR bumps it, and a story PR without a bump is not a review finding. Merging a version
bump to `main` publishes the release and its `v<version>` tag (`.github/workflows/release.yml`); a merge
without one publishes nothing. Before a release, bring AGENTS.md, README.md, docs/ and commands/ in
line with everything merged since the last tag. `merge --release` refuses the bump while `bin/`,
`commands/` or `hooks/` changed since that tag and README.md, AGENTS.md and `docs/` did not, unless
the release PR body has a `Docs: none — <reason>` line. Once the tag and the GitHub release are out,
`merge --release` updates the installed plugin and starts the new version's `swarm.sh upgrade` in
every project with running agents. It then prints a line asking the user to restart the lead
session (`/exit`, then `claude --continue`); the user does that, never the lead.

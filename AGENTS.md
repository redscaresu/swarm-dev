# AGENTS.md

swarm-dev is a Claude Code plugin that turns an agreed high-level design (HLD) into merged PRs.
Agents plan it into epics, split each epic into one-PR stories and build them in parallel, each in
its own herdr pane and git worktree.

Check these first. If any fails, stop and tell the user which one:

```bash
[ "$HERDR_ENV" = 1 ]            # you are inside a herdr pane; agents open in herdr workspaces (README: Workspace labels)
command -v swarm.sh             # the plugin is installed and this session started after it
gh auth status                  # PRs, checks and merges go through gh
git remote get-url origin       # a GitHub origin; swarm.sh resolves the owner from it
```

Then run these three, in order:

1. `swarm.sh init`, from the project's git root. It leaves the board (`docs/epics/`,
   `docs/stories/`), `.claude/swarm/` with a config, the `.gitignore` lines, a CI workflow and a
   pre-commit hook that run `make check`. With no `check` target in the Makefile, init says so;
   add one, or CI fails every change that is not board-only.
2. `/hld <title>` (the plugin's full name is `/swarm-dev:hld`). It leaves
   `docs/hld/<date>-<slug>.md`, a release's worth of work written with the user in its own pane.
   It stays `status: draft` until the user agrees it, then becomes `agreed`. Its `grants:` list
   what the swarm may do under it unasked: `epics`, `stories`, `merge`, `release`. Only the user
   sets them. One epic with no HLD starts with `/epic <title>` (`/swarm-dev:epic`) instead; it
   leaves `docs/epics/<slug>.md`, `active` once the user agrees it.
3. `/swarm-dev:swarm`. It reads the board with `swarm.sh next`, plans the HLD into epics, each
   epic into stories, builds them and loops until the user must decide. It leaves
   `docs/epics/<slug>.md` and `docs/stories/<slug>.md` files and one PR per story. With the
   default `merge = human` the user merges each PR, unless the HLD over it grants `merge`; with
   `merge = agent` the swarm merges them. Run it again after each decision.

The method, and why it is shaped this way, is in [`docs/method.md`](docs/method.md). Read it before
you run anything. [`docs/lead-by-hand.md`](docs/lead-by-hand.md) lists the steps a lead still
takes by hand, each with its open issue; every release removes the ones it fixes.
[`llms.txt`](llms.txt) maps the rest of the docs.

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
| HLD | `/hld <title>` | `docs/hld/<date>-<slug>.md`, a draft co-written in its own pane and attacked by a reviewer; `agreed` once the user agrees it, with the `grants:` only they set |
| Epics | `/plan-hld <hld>` | `docs/epics/<slug>.md` per epic, as drafts the user agrees one by one through `/epic`, or `active` at once when the HLD grants `epics` |
| Epic | `/epic <title>` | `docs/epics/<slug>.md`, a draft co-written in its own pane and attacked by a reviewer; `active` once the user agrees it |
| Stories | `/plan-epic <epic-slug>` | `docs/stories/<slug>.md` per story, after approval; a large epic is split into child epics first |
| Build | `swarm.sh conduct <epic-slug>` or `conduct --backlog` | a fresh conductor that starts the epic's builds (or the ready stories with no epic) and a review agent on each PR as it opens, and ends the epic with its report once no agent work is left; it never reviews or merges a PR. The review agent merges the PR, or hands it to the user with `merge = human` |

Useful while it runs:

- `swarm.sh status [--all]`: agents that need a look (including empty panes where a start failed), stacked builds whose parent moved or merged, and what waits on the user; `--all` lists idle agents and blocked stories too.
- `swarm.sh dash [--watch [seconds]]`, and `swarm.sh dash --project <dir>` (repeatable): the board, agents, running-now box, merges-per-day speedometer, model ladder and recent events on one read-only screen; each `--project` draws another project.
- `swarm.sh where <agent>`: the pane, workspace and tab of one of this project's agents. `swarm.sh swarms`: every swarm running on this machine.
- `swarm.sh tidy [--yes]`: close empty panes and retired agents' panes; lists them first.
- `swarm.sh next`: the next step, without doing it. It prints `release` when `main` has changes since the last `v<version>` tag, `stage v<T>` when staged draft epics can go active because the base has a tag at or above the minor before their stage, and `idle:` lines for capacity nothing uses (`dash` shows them too).
- `swarm.sh conduct <epic>|--backlog`: a fresh conductor for one epic, or for the ready stories with no epic. It starts builds and review agents, never reviews or merges a PR, and ends the epic with its report, written only once no agent work is left (the `finish:` line on a merge or handover note says so). `swarm.sh watch [--epic <slug>|--backlog] [repo...]` returns when a story PR needs the lead, and with `--epic` or `--backlog` also once when a story PR of theirs opens.
- `swarm.sh wait --lead`: returns when the lead's queue gains a held or escalated story, a green PR that waits on the user, an agent stuck on a prompt, a dialog, an expired login, an API error or manual mode, one of `next`'s `idle:` lines for blocked stories, for ready stories with no build and for an epic that can start or has no plan running, a reviewed story PR left unmerged past `queue_minutes` (`unmerged:`), a story PR that conflicts with its base (`conflict:`), or a review agent's stop note that no running conductor has (`stopped:`), among others: [§ The lead](docs/reference-lead.md#the-lead) in docs/reference-lead.md lists every line. It also starts a review agent itself: when a `review-agent` start was cut short with tries left, it runs the next try, and its `no-review:` line says `(started N of 3)`.
- `swarm.sh wait-pr --head <sha> <pr-url>`: wait for a PR's checks on <sha>; exit 0 green, 1 red, 2 on a gh error, a conflict with the base, no check runs or an expected workflow that never started within 5 minutes, a head that is still not <sha> by then, or the timeout. Without `--head` it waits on the head GitHub reports first, and right after a push that can still be the old one. Every CI wait goes through it; the guard refuses a hand-written `gh pr checks` loop.
- `swarm.sh review-agent <slug> <pr-url>`: a review agent for one PR, scoped to its story's `touches` and **Done when**. It never edits the PR's code. It waits for green, runs codex every round and `/code-review` on round 1 only, and decides which findings to fix and which to decline. It sends the ones to fix to the builder, then reviews the builder's next head in the same session. A round with nothing to fix, because the agent declines every finding as a nit, low value, out of scope or wrong, is a pass: the review agent merges the PR with `merge = agent` or an HLD `merge` grant, and otherwise hands it to the user. With `escalate_ladder` set, the `step_up_findings`-th findings round (default 3) hands the build to the next model. On the top rung, the `top_rung_rounds`-th round (default 2) goes to the lead.
- `swarm.sh outcomes` and `swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>]`: one row per build with its timings, and the project's numbers a section each: `cost`, `features`, `reviewers`, `throughput`, `time_in_state` (with time held ready while a conductor ran, and how long a ready story waited for its build) and more.
- `swarm.sh dataset`: write `.swarm/dataset.jsonl`, one JSON line per merged story, its plan beside what the build took.
- `swarm.sh policy <role>`: model and effort for a role.
- `swarm.sh tell <slug> <kind> <file>`: findings, nudge or resume sends an idle builder a file, and queues it for a busy one until its turn ends; `tell conduct-<epic> note <file>` appends it to a conductor's inbox, busy or not.
- `swarm.sh merge [--board|--release] <pr-url>`: merge a green PR in review with its head pinned, wait for CI on main, then reconcile; `--release` merges the lead's version-bump PR. When the base gained more than board files since the PR's CI ran, a story PR's merge merges the base into the PR's branch and waits for CI on that head; it holds a PR that costs money or changes a protected path for the user, and a story or `--board` PR whose own merge of the base dropped a line of the base, or whose merges it cannot check ([reference-merging.md § Merging](docs/reference-merging.md#merging)). After a story merge it sends the story's running conductor a note that the PR merged, naming the stories it made ready. After a `--board` merge it pulls the board and sends each running conductor a note naming the stories that merge made ready. When reconcile fails, either note still goes, naming the failure. Where the base has a merge queue it enqueues the PR. When CI on main goes red on a commit it merged, it prints `fix-main:` and writes a `fix-main-<sha>` story, which `next` names first. With `merge_admin = on` it passes `--admin` once its own checks pass. In a swarm project the plugin's guard hook refuses any other merge.
- `swarm.sh step-up <slug> <trigger>`: hand a struggling build to the next model in `escalate_ladder` (off by default), on the same branch, without counting an attempt. With the ladder set, swarm.sh runs it itself on `no-pr`, `stalled`, `findings-3` and `ci-red-2`. `step-up --resume <slug>` starts a rung whose start failed.
- `swarm.sh intervene lead-hand|user-caught "<one line>"`: log a time a person had to step in; `flow` and `dash` count them.
- `swarm.sh dash --check`: compare each figure dash shows with the command that owns it.
- `swarm.sh log-finding [--declined <reason> | --filed] [--reviewer <who>] [--round <n>] <kind> <pr> <text>`: the outer loop. Log findings by kind, with the reason for a declined one, who raised it (codex, fallback, code-review, ci, conductor, lead, skeptic, critic, split-critic, or escaped) and the review round (0 for a plan or board PR), which flow's `reviewers` section counts per round. `outcomes`' recurring block lists kinds fixed on 3+ PRs, and `/swarm-dev:swarm` files a `checks:` story for each.
- `herdr agent read <name> --source recent-unwrapped`: what an agent is doing.

**Rules that are not negotiable:**

- You supervise; the agents do the work. Do not write an epic or story plan yourself when a
  command exists for it. The exception is a small epic (three stories or fewer, none `risk: high`),
  which `/plan-epic` has the lead plan alone.
- Never merge a PR whose checks are not all green on its head commit. With `merge = human` (the
  default), never merge, with two exceptions: a PR whose agreed HLD grants `merge`
  (`swarm.sh grants <PR URL>`), and the version bump when every story merged since the last tag is
  under an HLD that grants `release`. Otherwise `swarm.sh review <slug> <PR URL>` hands it to the
  user.
- Agents start with an allowlisted environment (`AGENT_ENV` in bin/lib/agents.sh, plus `LC_*`,
  `SWARM_*` and `XDG_*`). Any other variable you exported reaches an agent only when its story names
  it under `env:` or the board's config lists it in `agent_env`. With Foundry on
  (`CLAUDE_CODE_USE_FOUNDRY`), the session's `ANTHROPIC_FOUNDRY_*` and
  `ANTHROPIC_DEFAULT_<MODEL>_MODEL` settings pass to every agent too.
- The plugin's guard hook refuses a raw merge, a `cd <dir>` followed by `;` (write
  `cd <dir> || exit 1 &&`), a `git checkout` that drops uncommitted changes, a `git reset --hard`,
  `restore` or `clean` that would drop uncommitted changes or untracked files in the main checkout
  (in any session, the lead's too), and, for an agent, `git checkout`, `switch`, `restore`,
  `reset --hard`, `stash` or `clean` in the main checkout, `pkill`, `killall` and `gh pr checks`
  loops (reference-merging.md § Merging).
- Never hand a `kind: lead` story (real cloud, credentials, or a step that is the user's) to an
  agent. List them for the user.
- One conductor per epic. Two stories clash only when their `touches` name the same file in the same repo and
  the same first word of a part (past a leading `§`, `#`, "the", "a" or "an"), or both name the bare file; clashing stories in two epics get a `depends_on`. Only the lead
  edits the shared files the project's `AGENTS.md` names.
- A question for the user is a `kind: lead` story with a **You:** step, not a line in chat.
- Remove nothing a board sets (a config key, a story or epic field, a brief form the guard accepts)
  until every board the user runs has been checked for it. swarm-dev has no list of those boards:
  the planner asks the user to name them, and the removal PR quotes the check on each. A removed
  key in `REMOVED_KEYS` still loads for at least one release: it is ignored, with a warning on
  stderr naming it and its line (`tests/removed_test.sh` pins this).
- A fix to the swarm's own loop (the conductor, review agent, guard or `wait` commands) ships as a
  patch release soon after it merges, so running projects get it. The lead cuts it, through the
  release arm below; a builder's story PR never bumps the version.
- Docs move with behaviour: a PR that changes what a user runs, sees or must do updates every doc
  that states it (README.md, AGENTS.md, `docs/`, `commands/`, `skills/swarm-dev/`) in the same PR, never a later one.

## Working on this repository

```
bin/swarm.sh          the entry point: usage, settings, the model policy, the command dispatch
bin/lib/*.sh          the commands by group (agents, board, build, dash, lifecycle, merge, reports)
bin/lib/*.py          the Python helpers the commands run
bin/gh-shim           the gh every agent runs: logs each call to .swarm/gh-calls.tsv, then runs the real gh
commands/             /epic, /plan-epic, /swarm (Markdown the plugin loads)
hooks/                hooks.json; merge-guard.sh (the guard on merges and commands that lose work), agent-state.sh
                      (an agent's state for herdr), lead-stop.sh (the lead's turn ends only when next allows),
                      lead-session.sh (sourced: tells the lead's session from an agent's) and
                      user-caught-reminder.sh (reminds the lead to log a time a person had to step in)
scripts/              test.sh (the make test runner), select-tests.sh and select_tests.py (the tests a branch's
                      changes map to), test-map.tsv (that map), lint (make check: JSON a test feeds must
                      parse), pre-commit, board-only.sh
tests/                *_test.sh, run by make test; doc_check_test.sh checks the docs name only what swarm.sh has
docs/method.md        the method; change it when behaviour changes
docs/reference*.md    every rule, setting, command and log; reference.md lists which file holds each §
board/                this repo's own board (board_dir = board); docs/ holds user docs only
skills/swarm-dev/     the plugin skill that answers "how do I use swarm-dev?"
templates/docs/       what a project copies: the board formats and Obsidian views
.claude-plugin/       plugin and marketplace manifests
```

Before you open a PR:

```bash
make hooks                                  # once: the gitleaks pre-commit hook
shellcheck bin/swarm.sh bin/lib/*.sh bin/gh-shim/gh hooks/*.sh scripts/pre-commit scripts/demo-dash.sh scripts/board-only.sh scripts/test.sh scripts/select-tests.sh tests/*.sh
python3 -m py_compile bin/lib/*.py scripts/select_tests.py
make check                                  # scripts/lint over tests/*_test.sh
scripts/select-tests.sh --run               # before a push: the tests mapped to what the branch changed, at JOBS=4
                                            # a changed file the map does not know runs the full suite
# make test                                # optional, the whole suite: every tests/*_test.sh: in parallel, SLOW files first, SERIAL ones alone
                                            # a file past TEST_FILE_TIMEOUT (600 s, 3x for SLOW) is killed and fails as TIMEOUT
                                            # each file runs from its own TMPDIR with SWARM_PROJECT naming a stand-in project, and fails
                                            # if its swarm.sh reaches it; an unpinned swarm.sh call stops there; dash starts no detached refresh
claude plugin validate .
```

Run `scripts/select-tests.sh --run` before a push. CI's sharded run is the gate: `test` is the
required check, and it passes when its 12 `test-shard` jobs do. The full `make test` is for when you
want the whole suite locally.

Development rules for anyone, agent or person, working in this repository:

- Run tests only through `make test` or `scripts/select-tests.sh --run`, never a test file by hand.
- Unset `SWARM_PROJECT` for any test-like command run outside `make test` (a `swarm.sh` call by
  hand, a hook): a builder's shell exports it, and the call then reaches the real repo.
  `make test` already unsets it.
- Never run `flow`, `dash`, `outcomes` or `dataset` against the real repo in a loop, in parallel or
  over days, even when a story's Done when names a multi-day window. Run it once, after
  `gh api rate_limit`, and say so in the PR: `flow` and `outcomes` with `--since <today>`, `dash` and
  `dataset` as they are (they take no `--since`). After a test run, check that no `dash_slow.py` or
  `swarm.sh flow --since` from your worktree is left. Kill by PID only what names your worktree or
  a test temp dir.
- A stress or load run uses at most 4 CPUs in all, with `make test` at `JOBS=4` or fewer, and you
  tear every load process and container down when the check ends.
- Prove a mutation without git: copy the file aside, break the original, then copy it back. With
  more than two proofs, or one on a SLOW test file, break the fix in a copy of the worktree without
  `.git`, run `make test TESTS=<file> JOBS=1 TEST_RUNS_LOG=` there, keep the FAIL lines and delete
  the copy. Say in the PR that you used the worktree copy. Never use `git checkout` or
  `git restore` on uncommitted work.

The machine-wide cap on `make test` is the file `~/.swarm/test-cap`, read only by `scripts/test.sh`.
A whole number N lets at most N runs go at once on the machine, whatever their project. A run waits
for a free slot under `~/.swarm/test-slots/`. The wait has no time limit: a holder that is stopped (Ctrl-Z) or hung keeps its slot until it ends or you `rm -r` the slot directory the waiting message names. A missing file, an empty file or 0 means no cap, and
nothing is made under `~/.swarm`. A `make test` that a test starts inside another run is nested: it
skips the cap and takes no slot. It is no `swarm.sh` setting, so it is not in `CONFIG_KEYS` or
reference-models.md's settings table.

Every `tests/*_test.sh` sources `tests/test_helpers.sh` as its first command after `set -euo pipefail`. It
drops the pane's `SWARM_*` settings and `HERDR_SOCKET_PATH`, which name the lead's real project and herdr.
`make test` runs each file from its own `TMPDIR`, where a `swarm.sh` call a test leaves unpinned (no `cd`
into a project of its own, no `SWARM_PROJECT` on the call) stops at "not in a swarm project", and with
`SWARM_PROJECT` naming a stand-in project, failing a file whose `swarm.sh` reaches it. Both name the
checkout the tests run from (its main checkout, from a worktree) in `SWARM_FORBID_PROJECT`, and `swarm.sh`
refuses to act on that project, named directly or through a worktree of it, so such a `swarm.sh` call stops
before it writes. That covers `swarm.sh` calls; the hooks' own event lines (`hooks/merge-guard.sh` `record`,
`hooks/lead-stop.sh` `log`) append to the project under the call's cwd and are not covered. `tests/live_logs_test.sh` checks the source line in every file and the runner's check, that
`events_test.sh`, whose fixtures once reached the real logs, leaves a copy of the checkout's `findings.tsv`,
`events.tsv` and `.swarm/lead/pid` as they were under `make test`, and that a test naming the copy, or a
worktree of it, is refused and writes nothing there.

Before the PR opens, run the humanizer skill (`humanizer:humanizer`) over the prose it changes for people to
read: README.md, docs/, epics, the text in commands/ that the user sees, and the PR description. Say
in the PR that you did. Story files and briefs are written for agents and need no pass.

Secrets are stopped at three layers: the pre-commit hook, the CI gitleaks job over the full
history (required on `main`), and GitHub push protection. Keep template links as markdown links,
never `[[wikilinks]]`.

`bin/swarm.sh` and `bin/lib/*.sh` must run on macOS's bash 3.2: no `mapfile`, no associative arrays. Pin every GitHub
Action to a commit SHA, with `persist-credentials: false` and read-only permissions; zizmor fails
the PR otherwise. CI (shellcheck, test, plugin-validate, gitleaks, zizmor) is required on `main`; `test` passes when its 12 `test-shard` jobs do (`SHARD=i/N` runs one locally).
When `swarm.sh next` prints `release` (`main` has changes since the last `v<version>` tag), the lead cuts a
release through `/swarm-dev:swarm`'s release arm and `swarm.sh merge --release`: a PR that bumps `version` in
`.claude-plugin/plugin.json` and nothing else. `claude plugin update` fetches nothing while the version is
unchanged. No story PR bumps it, and a story PR without a bump is not a review finding. Merging a version
bump to `main` publishes the release and its `v<version>` tag (`.github/workflows/release.yml`); a merge
without one publishes nothing. Before a release, bring AGENTS.md, README.md, docs/ and commands/ in
line with everything merged since the last tag. `merge --release` refuses the bump while `bin/`,
`commands/` or `hooks/` changed since that tag and README.md, AGENTS.md and `docs/` did not, unless
the release PR body has a `Docs: none — <reason>` line.

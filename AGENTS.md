# AGENTS.md

swarm-dev is a Claude Code plugin that turns an agreed high-level design (HLD) into merged PRs.
Agents plan it into epics, split each epic into one-PR stories and build them in parallel, each in
its own herdr pane and git worktree.

Check these first. If any fails, stop and tell the user which one:

```bash
[ "$HERDR_ENV" = 1 ]            # you are inside a herdr pane; agents open in herdr workspaces (docs/running.md: Workspace labels)
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
- `swarm.sh where <agent>`: the pane, workspace and tab of one of this project's agents. `swarm.sh swarms`: every swarm running on this machine.
- `swarm.sh tidy [--yes]`: close empty panes and retired agents' panes; lists them first.
- `swarm.sh next`: the next step, without doing it. It prints `release` when `main` has changes since the last `v<version>` tag and every one is a fix (a patch), `retro v<x.y.z>` before a minor release that no done retro file covers, `stage v<T>` when staged draft epics can go active because the base has a tag at or above the minor before their stage, and `idle:` lines for capacity nothing uses.
- `swarm.sh conduct <epic>|--backlog`: a fresh conductor for one epic, or for the ready stories with no epic. It starts builds and review agents, never reviews or merges a PR, and ends the epic with its report, written only once no agent work is left (the `finish:` line on a merge or handover note says so). `swarm.sh watch [--epic <slug>|--backlog] [repo...]` returns when a story PR needs the lead, and with `--epic` or `--backlog` also once when a story PR of theirs opens.
- `swarm.sh watch --epic <slug>`, with no repos named, also returns `epic-done: <slug> has no agent work left` (exit 0) on a poll where the epic has no agent work left by the `finish:` line's rule and no PR of its stories is open, so the conductor writes its report.
- `swarm.sh wait --lead`: returns when the lead's queue gains a held or escalated story, a green PR that waits on the user, an agent stuck on a prompt, a dialog, an expired login, an API error or manual mode, one of `next`'s `idle:` lines for blocked stories, for ready stories with no build and for an epic that can start or has no plan running, a reviewed story PR left unmerged past `queue_minutes` (`unmerged:`), a story PR that conflicts with its base (`conflict:`), a review agent's stop note that no running conductor has (`stopped:`), a plan swarm whose agents have all written their output (`planned:`) or one that ended without it (`plan-missing:`), or a `usage:` warning once the usage estimate passes `usage_warn_percent`, among others: [§ The lead](docs/reference-lead.md#the-lead) in docs/reference-lead.md lists every line.
  A run with nothing new to report ends on `timeout:` (exit 1), `replaced:` when a newer run took over (exit 143), or `wait-failed: exit <rc>` on an error; a run killed outright or stopped before it started prints nothing (docs/reference-lead.md says when).
  It also starts a review agent itself: when a `review-agent` start was cut short with tries left, it runs the next try, and its `no-review:` line says `(started N of 3)`.
- `swarm.sh wait-pr --head <sha> <pr-url>`: wait for a PR's checks on <sha>; exit 0 green, 1 red, 2 on a gh error, a conflict with the base, no check runs or an expected workflow that never started within 5 minutes, a head that is still not <sha> by then, or the timeout. Without `--head` it waits on the head GitHub reports first, and right after a push that can still be the old one. Every CI wait goes through it; the guard refuses a hand-written `gh pr checks` loop.
- `swarm.sh review-agent <slug> <pr-url>`: a review agent for one PR, scoped to its story's `touches` and **Done when**.
  It never edits the PR's code.
  It waits for green, runs codex alone every round, and decides which findings to fix and which to decline.
  It sends the ones to fix to the builder, then reviews the builder's next head in the same session.
  From round 2 (the round cap) it sends only a regression the PR introduces or a line now false about the code, and declines the rest as deferred.
  A round with nothing to fix, because the agent declines every finding as a nit, low value, out of scope, wrong or deferred, is a pass: the review agent merges the PR with `merge = agent` or an HLD `merge` grant, and otherwise hands it to the user.
  With `escalate_ladder` set, the `step_up_findings`-th findings round (default 3) hands the build to the next model.
  On the top rung, the `top_rung_rounds`-th round (default 2) goes to the lead.
- `swarm.sh outcomes` and `swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>]`: one row per build with its timings, and the project's numbers a section each: `cost`, `features`, `reviewers`, `throughput`, `time_in_state` (with time held ready while a conductor ran, and how long a ready story waited for its build) and more.
- `swarm.sh retro [--since <tag>] [--memory <dir>]`: the release retro's report since a tag (default the newest `v<x.y.z>` tag), one section per list the lead goes through with the user before a minor release. It is read-only and makes no gh call.
- `swarm.sh handover <dir> [--memory <dir>]`: write what another machine needs that git does not carry into a new or empty folder outside the repo: `.swarm/` without session logs, agent session ids or files named like a credential, a patch of the main checkout's uncommitted board edits, a snapshot of open PRs and agents, and a RESTORE.md with the commands that restore each into a fresh clone. The lead's memory folder goes in only with `--memory`.
- `swarm.sh dataset`: write `.swarm/dataset.jsonl`, one JSON line per merged story, its plan beside what the build took.
- `swarm.sh policy <role>`: model and effort for a role.
- `swarm.sh tell <slug> <kind> <file>`: findings, nudge or resume sends an idle builder a file, and queues it for a busy one until its turn ends; `tell conduct-<epic> note <file>` appends it to a conductor's inbox, busy or not.
- `swarm.sh merge [--board|--release [--upgrade]] <pr-url>`: merge a green PR in review with its head pinned, wait for CI on main, then reconcile; `--release` merges the lead's version-bump PR, and for swarm-dev's own release moves the running agents onto it only with `--upgrade` or a yes typed at a terminal.
  When the base gained more than board files since the PR's CI ran, a story PR's merge merges the base into the PR's branch and waits for CI on that head; it holds a PR that costs money or changes a protected path for the user, and a story or `--board` PR whose own merge of the base dropped a line of the base that its head has not put back, or whose merges it cannot check ([reference-merging.md § Merging](docs/reference-merging.md#merging)).
  With `merge_protected = on` and `merge = agent` it does not hold a story PR for a protected path: it names the path and the setting, then merges it.
  After a story merge it sends the story's running conductor a note that the PR merged, naming the stories it made ready.
  After a `--board` merge it pulls the board and sends each running conductor a note naming the stories that merge made ready.
  When that PR is an epic's Finish PR, it closes the epic's conductor once the merge has exited, the conductor is idle and the lead has tried to close it since its report.
  When reconcile fails, either note still goes, naming the failure.
  Where the base has a merge queue it enqueues the PR.
  When CI on main goes red on a commit it merged, it prints `fix-main:` and writes a `fix-main-<sha>` story, which `next` names first.
  With `merge_admin = on` it passes `--admin` once its own checks pass.
  In a swarm project the plugin's guard hook refuses any other merge.
- `swarm.sh step-up <slug> <trigger>`: hand a struggling build to the next model in `escalate_ladder` (off by default), on the same branch, without counting an attempt. With the ladder set, swarm.sh runs it itself on `no-pr`, `stalled`, `findings-3` and `ci-red-2`. `step-up --resume <slug>` starts a rung whose start failed.
- `swarm.sh intervene lead-hand|user-caught <cause> "<one line>"`: log a time a person had to step in, and why (a cause from `INTERVENE_CAUSES` in bin/swarm.sh; an unknown one fails and lists them); `flow` counts them.
- `swarm.sh log-finding [--declined <reason> [--because <why>] | --filed] [--reviewer <who>] [--round <n>] <kind> <pr> <text>`: the outer loop. Log findings by kind, with the reason for a declined one (and with `--because` the builder's own reason, which codex sees on the PR's next review), who raised it (codex, fallback, code-review, ci, conductor, lead, skeptic, critic, split-critic, or escaped) and the review round (0 for a plan or board PR), which flow's `reviewers` section counts per round. `outcomes`' recurring block lists kinds fixed on 3+ PRs, and `swarm.sh retro`'s recurring list names each one with no check before a minor release.
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
  `ANTHROPIC_DEFAULT_<MODEL>_MODEL` settings pass to every agent too. With Bedrock on
  (`CLAUDE_CODE_USE_BEDROCK`), so do `AWS_BEARER_TOKEN_BEDROCK` and the model settings. On a
  Claude subscription nothing extra passes: the login lives under `CLAUDE_CONFIG_DIR` (or
  `~/.claude`), which every agent already gets.
- The plugin's guard hook refuses a raw merge, a `cd <dir>` followed by `;` (write
  `cd <dir> || exit 1 &&`), a `git checkout` that drops uncommitted changes, a `git reset --hard`,
  `restore` or `clean` that would drop uncommitted changes or untracked files in the main checkout
  (in any session, the lead's too), and, for an agent, `git checkout`, `switch`, `restore`,
  `reset --hard`, `stash` or `clean` in the main checkout, `pkill`, `killall` and `gh pr checks`
  loops (reference-merging.md § Merging).
  It also refuses an agent's `make test` with no `TESTS=` where the checkout has `scripts/select-tests.sh`.
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
  patch release soon after it merges. The lead cuts it, through the
  release arm below; a builder's story PR never bumps the version.
  The release moves `prerelease`, so the machine on `swarm-dev@swarm-dev-pre` gets the fix at once.
  Every other machine follows `stable`, which the lead moves when the stage ends, so it gets the fix then.
  It ships as a patch only when every change since the tag is from a `fix: true` story or a fix-main build.
  In swarm-dev's own repo, a PR that changes only files under `tests/`, and a `port: true` story's PR whose changed `tests/` files are all in its `touches`, ship as a patch too.
  Otherwise `merge --release` refuses the patch, and the fix ships in the next minor, after its retro.
- Docs move with behaviour: a PR that changes what a user runs, sees or must do updates every doc
  that states it (README.md, AGENTS.md, `docs/`, `commands/`, `skills/swarm-dev/`) in the same PR, never a later one.
- In the docs, a new event, field, line kind, flow section, setting or command goes in as its own
  list item or block, at its sorted place, one sentence per line.
  Never lengthen a table row, or a sentence that lists them: git conflicts by line, so two PRs that
  extend one line clash.
  `tests/doc_check_test.sh` fails any line over 150 words outside a code fence, but it cannot catch a
  short sentence that many PRs extend.

## Working on this repository

```
bin/swarm.sh          the entry point: usage, settings, the model policy, the command dispatch
bin/lib/*.sh          the commands by group (agents, board, build, lifecycle, merge, reports)
bin/lib/*.py          the Python helpers the commands run
bin/gh-shim           the gh every agent runs: logs each call to .swarm/gh-calls.tsv, then runs the real gh
go.mod                the Go module github.com/redscaresu/swarm-dev: the Go port of swarm.sh, standard library only
cmd/swarm/            the Go command, the wiring layer: the table of entries by name and the frame bash hands
                      over (frame.go); no command is ported yet, and wrapper-fixture is for the wrapper's tests
                      bridge.go runs a form still in bash as `bash bin/swarm.sh _<name>`
internal/iface/       the four interfaces the rules packages take (agent runner, code host, repo, store),
                      the store's two methods for the frame's files and the store's types
internal/adapter/     the one implementation of each: herdr/, gh/, git/ (each runs its program from PATH)
                      and store/ (.swarm/, the board's files and the frame's die and fields files)
internal/clock/       the one package that may read the time
internal/layers/      the Go checks that give each package its layer, in tests only
commands/             /epic, /plan-epic, /swarm (Markdown the plugin loads)
hooks/                hooks.json; merge-guard.sh (the guard on merges and commands that lose work), agent-state.sh
                      (an agent's state for herdr), lead-stop.sh (the lead's turn ends only when next allows),
                      lead-session.sh (sourced: tells the lead's session from an agent's) and
                      user-caught-reminder.sh (reminds the lead to log a time a person had to step in)
scripts/              test.sh (the make test runner), select-tests.sh and select_tests.py (the tests a branch's
                      changes map to), test-map.tsv (that map), lint (make check: JSON a test feeds must
                      parse, no test pipes into grep -q, and bin/lib's Python reads now and today only
                      through bin/lib/clock.py), pre-commit, board-only.sh
scripts/build.sh      the release contract: builds the four swarm-<os>-<arch> binaries and SHA256SUMS into dist/;
                      --list prints the assets, checksum file and signer without running go
tests/                *_test.sh, run by make test; doc_check_test.sh checks the docs name only what swarm.sh has
docs/method.md        the method; change it when behaviour changes
docs/reference*.md    every rule, setting, command and log; reference.md lists which file holds each §
board/                this repo's own board (board_dir = board); docs/ holds user docs, and docs/port/ is the one
                      contributor folder under it: the lists the Go port is checked against
skills/swarm-dev/     the plugin skill that answers "how do I use swarm-dev?"
templates/docs/       what a project copies: the board formats and Obsidian views
.claude-plugin/       plugin and marketplace manifests
```

Before you open a PR:

```bash
make hooks                                  # once: the gitleaks pre-commit hook
shellcheck bin/swarm.sh bin/lib/*.sh bin/gh-shim/gh hooks/*.sh scripts/pre-commit scripts/*.sh tests/*.sh
python3 -m py_compile bin/lib/*.py scripts/select_tests.py
make check                                  # scripts/lint over tests/*.sh and bin/lib/*.py
gofmt -l .                                  # must print nothing
go vet ./...
go test ./...
scripts/select-tests.sh --run               # before a push: the tests mapped to what the branch changed, at JOBS=4
                                            # it never runs the full suite: it names each changed file that would select every test,
                                            # which CI's full run covers, and runs the tests for the rest
# make test                                # optional, the whole suite: every tests/*_test.sh: in parallel, SLOW files first, SERIAL ones alone
                                            # the guard refuses it in an agent's session; an agent names TESTS= or runs select-tests.sh --run
                                            # a file past TEST_FILE_TIMEOUT (600 s, 3x for SLOW) is killed and fails as TIMEOUT
                                            # each file runs from its own TMPDIR with SWARM_PROJECT naming a stand-in project, and fails
                                            # if its swarm.sh reaches it; an unpinned swarm.sh call stops there
                                            # before any file runs, it builds ./cmd/swarm once and hands it to every test in SWARMDEV_BIN
                                            # it needs go on PATH: with no go, or a build that fails, it fails before any file runs
claude plugin validate .
```

Run `scripts/select-tests.sh --run` before a push. It never runs the full suite, even for a file the
map does not know. CI's sharded run is the gate: `test` is the required check, and it passes when its
14 `test-shard` jobs do. The full `make test` is for when you want the whole suite locally.
`make test` needs Go wherever it runs, and so does `scripts/select-tests.sh --run`, which runs make test.
Each run builds `./cmd/swarm` from the tree it runs in, once, before any test file starts.
When a test starts a make test of the same tree while the run that built the binary is still going, that make test reuses the binary and builds nothing.

The `speed` job (`.github/workflows/speed.yml`) runs on each PR that is not board-only.
It installs strace, then runs `tests/speed_run.sh --require-count` with the PR's base as tree a and the PR's merge commit as tree b.
The merge commit is the head merged into the base, which GitHub checks out, so the run measures only the PR's own change.
Its log has one row for each command in `tests/speed_list.txt`, with each tree's median wall time and process starts.
It fails a command the merge commit runs slower than the base by more than 20% and at least 100 ms, and a run where strace cannot count.
A self-check step then times a copy of the merge commit with one extra exec (`/usr/bin/true` after `bin/swarm.sh`'s shebang) on the `usage` command.
It fails unless the copy counts exactly one more process start than the merge commit.
A run by hand (`workflow_dispatch`) takes a `base` ref, such as a tag, to time the dispatched ref against.
It is not a required check, but `swarm.sh merge` waits for it like every other pull_request workflow, and a red run holds the merge.
A port epic adds each command it ports to `tests/speed_list.txt`, one fixture name to a line.
Each name needs a fixture `fx_<name>` in a `tests/diff_fixtures_<area>.sh` file, or the run is red.

`tests/diff_run.sh` is the differential run: it runs each fixture against two trees and compares what the two runs did.
A fixture is an `fx_<name>` function in a `tests/diff_fixtures_<area>.sh` file, and the run loads every such file.
The `diff-run` job (`.github/workflows/diff-run.yml`) runs `tests/diff_run.sh --base <base> <head>` on each PR, and runs the merge fixtures ten times, head against head.
`--base` applies only the allow-list entry of the head's own story, `scripts/allow/stage-<n>/<slug>.md` for branch `story/<slug>`.
So a port PR passes only with no difference, and a PR that changes output on purpose adds its story's entry in the same PR, naming each difference by its exact lines.
`scripts/allow/README.md` gives the entry format, and `--draft` prints the hunks to start from.
The job has no push trigger, so main's CI after a merge does not wait for it.

Development rules for anyone, agent or person, working in this repository:

- Run tests only through `make test` or `scripts/select-tests.sh --run`, never a test file by hand.
- Go layers: a rules package (every package but `cmd/` and those under it, `internal/iface`, `internal/clock` and the four adapters under `internal/adapter/`) starts no process, touches no file, uses no network and imports no adapter.
  Only `internal/clock` reads the time.
  Wiring imports no `os/exec` either, except `cmd/swarm/bridge.go`, which hands a form still in bash to `bin/swarm.sh` and goes with the last one.
  The four protected packages (`internal/guard/`, `internal/merge/`, `internal/release/` and `internal/agentenv/`) import no package of the module but each other, `internal/iface` and `internal/clock`.
  `internal/layers` holds the checks, and `go test -v ./internal/layers/` prints what each covers.
- A PR that adds a `SWARM_` name, a lock take site, an inline Python site or a test that reaches inside the code adds its row under `docs/port/`; [docs/port/README.md](docs/port/README.md) says which list holds what.
- In a test or a helper under `tests/`, never pipe into `grep -q`: under `pipefail` the pipeline
  returns 141 once grep's input passes 64 KB, since grep exits at its first match and the writer
  gets SIGPIPE.
  Write `grep -q <pattern> <<< "$(...)"`, or drop the `-q` and send grep's output to `/dev/null`.
  `make check` fails such a line; one that only quotes the pipe (a doc's text) says
  `# grep-q-pipe: ok, <why>` on its line or its heredoc's `<<` line.
- Unset `SWARM_PROJECT` for any test-like command run outside `make test` (a `swarm.sh` call by
  hand, a hook): a builder's shell exports it, and the call then reaches the real repo.
  `make test` already unsets it.
- Never run `flow`, `outcomes`, `retro` or `dataset` against the real repo in a loop, in parallel or
  over days, even when a story's Done when names a multi-day window. Run it once, after
  `gh api rate_limit`, and say so in the PR: `flow` and `outcomes` with `--since <today>`, `retro` and
  `dataset` as they are (`dataset` takes no `--since`; `retro` takes a tag). After a test run, check that no
  `swarm.sh flow --since` from your worktree is left. Kill by PID only what names your worktree or
  a test temp dir.
- A stress or load run uses at most 4 CPUs in all, with `make test` at `JOBS=4` or fewer, and you
  tear every load process and container down when the check ends.
- Prove a mutation without git. Before the PR opens, copy the file aside, break the original, then
  copy it back. After the PR opens, prove it on a copy of the worktree without `.git`, never in
  place: a broken file in the worktree leaves it dirty, and the review agent refuses to start. Make
  the copy in a new directory outside the worktree, as a copy inside it leaves the worktree dirty
  too. Use the copy before the PR opens too when you have more than two proofs, or one on a SLOW
  test file.
  In the copy, break the fix, run `make test TESTS=<file> JOBS=1 TEST_RUNS_LOG=`, keep the FAIL
  lines and delete the copy.
  make test in the copy builds the copy's own Go, so a fix in Go is tested there too.
  If the copy's Go does not build, the run fails before any test file starts.
  Say in the PR that you used the worktree copy. Push what is ready, and
  put further points in the PR body rather than in more pushes. Never use `git checkout` or
  `git restore` on uncommitted work.

The machine-wide cap on `make test` is the file `~/.swarm/test-cap`, read only by `scripts/test.sh`.
A whole number N lets at most N runs go at once on the machine, whatever their project. A run waits
for a free slot under `~/.swarm/test-slots/`. The wait has no time limit: a holder that is stopped (Ctrl-Z) or hung keeps its slot until it ends or you `rm -r` the slot directory the waiting message names. A missing file, an empty file or 0 means no cap, and
nothing is made under `~/.swarm`. A `make test` that a test starts inside another run is nested: it
skips the cap and takes no slot. It is no `swarm.sh` setting, so it is not in `CONFIG_KEYS` or
docs/method.md's settings table (§ Configuring a project).

Every `tests/*_test.sh` sources `tests/test_helpers.sh` as its first command after `set -euo pipefail`. It
drops the pane's `SWARM_*` settings and `HERDR_SOCKET_PATH`, which name the lead's real project and herdr.
`make test` runs each file from its own `TMPDIR`, where a `swarm.sh` call a test leaves unpinned (no `cd`
into a project of its own, no `SWARM_PROJECT` on the call) stops at "not in a swarm project", and with
`SWARM_PROJECT` naming a stand-in project, failing a file whose `swarm.sh` reaches it. Both name the
checkout the tests run from (its main checkout, from a worktree) in `SWARM_FORBID_PROJECT`, and `swarm.sh`
refuses to act on that project, named directly or through a worktree of it, so such a `swarm.sh` call stops
before it writes. The hooks' own event lines (`hooks/merge-guard.sh` `record`, `hooks/lead-stop.sh` `log`)
are not `swarm.sh` calls, so each hook checks `SWARM_FORBID_PROJECT` itself and writes no line to that project. `tests/live_logs_test.sh` checks the source line in every file and the runner's check, that
`events_test.sh`, whose fixtures once reached the real logs, leaves a copy of the checkout's `findings.tsv`,
`events.tsv` and `.swarm/lead/pid` as they were under `make test`, that a test naming the copy, or a
worktree of it, is refused and writes nothing there, and that both hooks, run from a worktree of the copy,
leave its `events.tsv` as it was.

A test that starts a background process calls `stop_test_group` from `tests/test_helpers.sh` in its EXIT trap, before it removes its temp root.
`make test` starts each file as the leader of its own process group.
A background job stays in that group with everything it starts, even after it is re-parented to init.
`stop_test_group` kills every other process in the group, so nothing the test leaves behind keeps writing into its root.
It spares a process whose parent is the test's parent, such as the `tail` in `bash tests/x.sh | tail`.
When the file does not lead its group, such as a file run by hand from a shell without job control, `stop_test_group` stops nothing.
A group the test makes itself with `in_new_group` is stopped by `stop_group`, or by `stop_groups` in the trap.
`tests/test_helpers_test.sh` checks it.

`tests/nopy_list.txt` lists the differential run's fixtures whose command must not start a program: one line per fixture, its name and then each program.
`tests/nopy_test.sh` runs each listed fixture through `tests/diff_run.sh` with those programs replaced on PATH by a stub that logs its call and exits 1.
It fails when the command starts one of them, even when the command swallows the failure.
The fixture's build and the gh and herdr stubs keep the real programs.
A program started by its absolute path is out of its reach.
A port epic adds a fixture's line once its command starts none of the programs the port removes, and adds a program to a line once the port drops it: python3 at stage 1, then awk, sed, perl and curl.

Before the PR opens, run the humanizer skill (`humanizer:humanizer`) over the prose it changes for people to
read: README.md, docs/, epics, the text in commands/ that the user sees, and the PR description. Say
in the PR that you did. Story files and briefs are written for agents and need no pass.

Secrets are stopped at three layers: the pre-commit hook, the CI gitleaks job over the full
history (required on `main`), and GitHub push protection. Keep template links as markdown links,
never `[[wikilinks]]`.

`bin/swarm.sh` and `bin/lib/*.sh` must run on macOS's bash 3.2: no `mapfile`, no associative arrays. Pin every GitHub
Action to a commit SHA, with `persist-credentials: false` and read-only permissions; zizmor fails
the PR otherwise. CI (shellcheck, test, plugin-validate, gitleaks, zizmor) is required on `main`; `test` passes when its 14 `test-shard` jobs do (`SHARD=i/N` runs one locally).
`go-checks` (`.github/workflows/go.yml`) is required on `main` too: it runs gofmt, go vet, go test and the Go layer checks.
`build-check` (`.github/workflows/build-check.yml`) is required on `main` too: on a PR that changes `.claude-plugin/plugin.json` it builds the four binaries and checks them against `scripts/build.sh --list`, and on every other PR it skips those steps and passes.
`macos-tests` (`.github/workflows/macos.yml`) runs `go test ./...` and a small subset of the bash tests on macOS arm64, under macOS's bash 3.2.
It is required on `main` too.
Before a minor release that no done retro file covers, `swarm.sh next` prints `retro v<x.y.z>`, and the lead goes
through the retro with the user first.
When `swarm.sh next` prints `release` (`main` has changes since the last `v<version>` tag and, for a numeric `x.y.z` tag, every one is a fix: a patch), the lead cuts a
release through `/swarm-dev:swarm`'s release arm and `swarm.sh merge --release`: a PR that bumps `version` in
`.claude-plugin/plugin.json` and nothing else. `claude plugin update` fetches nothing while the version is
unchanged. No story PR bumps it, and a story PR without a bump is not a review finding. Merging a version
bump to `main` publishes the release and its `v<version>` tag (`.github/workflows/release.yml`).
The workflow attaches the four binaries and `SHA256SUMS`, then moves `prerelease`.
It never moves `stable`; the lead does that when the stage ends.
A merge without a bump publishes nothing. Before a release, bring AGENTS.md, README.md, docs/ and commands/ in
line with everything merged since the last tag. `merge --release` refuses the bump while `bin/`,
`commands/` or `hooks/` changed since that tag and README.md, AGENTS.md and `docs/` did not, unless
the release PR body has a `Docs: none — <reason>` line.
In swarm-dev's own repo, that check also counts `cmd/`, `internal/` and `go.mod` as code.
It also refuses a minor bump with no done `<board>/retros/v<new>.md` on `main` covering it, and a patch bump while a change since origin's tag is not from a `fix: true` story or a fix-main build, under either merge setting ([§ The retro gate](docs/reference-merging.md#the-retro-gate)).
In swarm-dev's own repo, that patch check also passes a change only under `tests/`, and a `port: true` story whose `touches` list every `tests/` file it changes.

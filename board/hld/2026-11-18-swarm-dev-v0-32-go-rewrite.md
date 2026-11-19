---
title: swarm-dev v0.32: Go rewrite
date: 2026-11-18
status: agreed
grants: [epics, stories]
---

# swarm-dev v0.32: Go rewrite

v0.32 moves everything a user's machine runs from bash and Python to one Go binary, and changes
nothing else. The commands, flags, output, exit codes and files stay as they are. The swarm
builds it on itself, starting with the Python helpers, and the lead's machine runs each port before anyone
else gets it. The UI is v0.33 and the Lovable experience is v0.34; both build on the Go code.

Every spike in § Before this is agreed has its answer.

## Problem

The rewrite has no return today. The user wants it for maintainability, and because swarm-dev
will later move to Kubernetes or something like it: every later change gets easier in Go. All
counts are on `main` at `cfe2a200`, 2026-11-18.

- swarm-dev started as a small harness and grew fast. Its first commit is from 2026-09-29. Seven
  weeks later it is 33,682 lines with 52 version tags, 29 of them in the five weeks to
  2026-11-18.

- swarm-dev is two languages spliced together: 23,662 lines of bash in 15 files (`bin/swarm.sh`,
  8 files in `bin/lib/`, 5 hooks, the gh shim) and 10,020 lines of Python in 61 files (60 in
  `bin/lib/`, 1 in `scripts/`). The bash starts `python3` at 130 places: 82 with the code inline in
  the bash, 42 running a `bin/lib/*.py` file, 6 in other ways. `bin/swarm.sh:133` starts Python to
  read one field of `plugin.json`. Every such place passes its values across as text.
- The largest file, `bin/lib/lifecycle.sh`, is 6,355 lines; `merge.sh` is 3,797 and `board.sh`
  3,650. Nothing checks a function's arguments or a variable's type before it runs.
- The code must run on macOS's bash 3.2 (AGENTS.md § Working on this repository), which has no
  associative arrays and no `mapfile`. So state moves through global variables and temp files: a
  command's failure line goes through `DIE_FILE` and `DIE_LEVEL` (`bin/swarm.sh:70-82`), its event
  fields through another temp file (`bin/swarm.sh:84-99`).
- Whole classes of defect are held back by lint, one class at a time. #1007 rewrote 37 lines in
  the tests that piped into `grep -q`, which fails under `pipefail` once the input passes 64 KB,
  and added a lint for it. #1014 added a lint for clock reads in Python. The silent-swallow-lint
  story, for errors dropped unseen, was dropped on 2026-11-18 in favour of a rule in this rewrite.
  Nobody has counted how many of the 1,929 fixed findings in `.swarm/findings.tsv` a compiler
  would have stopped, and this design does not rest on that number.
- Work is waiting on the rewrite. 12 retro stories were folded into it on 2026-11-18 and not built
  in bash. Three kinds of finding logged that day (`false-conflict-line`,
  `dropped-lines-own-story-file`, `review-start-races-push`) and one stuck-builder incident
  (`.swarm/events.tsv`, 2026-11-18T15:08:26Z) were deferred to it too.
- The user on why now, 2026-11-17: "If we don't do it now it will only get worse." v0.33's UI is
  meant to read the board through the Go code's own structures.

Speed is no part of the case. The `status` timings in `.swarm/run-times.tsv` follow the machine's
load (a median of 102 s over the 23 runs at a load under 4, and 1,799 s over the 55 runs at 16
and over), so they say nothing about bash against Go.

## Goals

1. Everything a user's machine runs is Go: the 50 commands, the 5 hooks and the gh shim. The Go
   starts no `python3`, `awk`, `sed`, `perl` or `curl`. The check is a test that runs every
   command with a `python3` on `PATH` that fails loudly.
2. A port changes no behaviour. The check is a differential run: two trees run the same fixtures
   under the same stubs, and their stdout, stderr, exit codes, files written and calls to the
   stubs are the same. Each port PR runs it against the tree just before the port. Each stage's
   end runs it against the v0.31.2 tree, where the only differences allowed are the ones the
   `fix: true` stories since then made, each named, and the entries on the stage's allow list.
   The allow list names each change a stage makes on purpose (the wider holds, the patch gate's
   new cases, the wrapper's lines). Each entry cites its merged story and the exact lines, and the
   user agrees the list at the stage's exit.
3. Each rule has one implementation at any time, with three named exceptions (§ Exceptions to one
   implementation).
4. The lead's machine runs each port from the prerelease ref. Every other machine gets the ports
   when a stage ends. For each stage's trial the user's second Mac switches to
   `swarm-dev@swarm-dev-pre`, and back to `swarm-dev@swarm-dev` once the stable ref moves, which
   also checks that stable updates work.
5. A user installs and updates as today. Go is needed on a user's machine only as the fallback.
   The wrapper checks the binary's checksum and its build attestation before it runs it.
6. The 12 folded stories and 3 of the 4 deferred items land, each after the port of its command.
   The fourth, `dropped-lines` skipping a story PR's own story file, is fixed in bash before the
   freeze (the user, 2026-11-19).
7. No command is slower than its bash. The check runs in CI on a fixed fixture under stubs, and
   reports wall time and process starts per command before and after its port.
8. The names stay: `swarm.sh`, the hook paths in `hooks/hooks.json`, every setting and field.
9. The packages that hold the rules start no process and touch no file themselves (§ Layers). A
   CI check fails an import that crosses that line.

## Non-goals

- The UI (v0.33) and the Lovable experience (v0.34).
- A Kubernetes port, a replacement for herdr, or a second implementation of any of the four
  interfaces in § Layers. The design must rule neither move out.
- Making commands faster by changing the calls they make, such as herdr's snapshot or parallel
  `gh` calls. That is v0.33's, on the Go code.
- New features, settings or commands, other than the ones this design itself adds: the
  `port: true` story field, the wrapper's download and build, the patch gate's diff check, the
  wider protected paths, the two release refs, `swarm.sh` reading the installed plugin's ID, the macOS CI job, the import
  check, and the
  behaviour changes in § Folded work.
- Rewriting the tests in Go. The bash tests stay as the check from outside. The stage 1 list
  (§ Tests) names the few that become Go tests, and the user agrees that list.
- Porting what only contributors and CI run: `scripts/test.sh`, `scripts/select-tests.sh`,
  `scripts/select_tests.py`, `scripts/lint`. `scripts/lint`'s clock rule reads `bin/lib`'s Python
  and goes when that does; a Go check takes its place (§ Go rules).
- Replacing the `git`, `gh` or `herdr` programs with libraries or APIs.
- Changing any file format or lock protocol under `.swarm/` or on the board.
- Third-party Go modules in the binary. `staticcheck` and `errcheck` are tools CI installs,
  pinned by version and hash.
- Windows.

## Current state

- `bin/swarm.sh` (1,368 lines) is the entry point. It loads the config (`:273`), sources the 8
  files in `bin/lib/` (`:561-575`) and dispatches (`:622`): 50 commands, and 18 internal ones
  whose names start with `_`. `main` (`:1287`) logs every command that changes something to
  `.swarm/events.tsv`.
- The 60 Python helpers in `bin/lib/` import only the standard library and each other. Each runs
  as its own process and takes text. The largest are `dash_render.py` (1,060 lines), `ci_gate.py`
  (958) and `panes.py` (548).
- Three helpers run inside the bash process. `fm` reads front matter (`bin/lib/board.sh:7`) and
  answers from a snapshot during a report, starting no process. The config is shell variables set
  once (`bin/swarm.sh:273`). Event lines are appended by a bash function
  (`bin/lib/agents.sh:983`). Front matter is read on about 257 lines, the config on 104 and events
  written on 81 (the reviewer's count).
- `hooks/hooks.json` runs `merge-guard.sh` before every Bash tool call, with no timeout, in every
  session where the plugin is on. Most calls leave on a bash fast path. With `python3` missing, a
  command that says merge is refused and the rest pass (`hooks/merge-guard.sh:45`). The other
  hooks are `agent-state.sh`, `lead-stop.sh` and `user-caught-reminder.sh`, with
  `lead-session.sh`, which two of them source. The five are 1,095 lines.
- `bin/gh-shim/gh` (123 lines) goes first on `PATH` (`bin/swarm.sh:217-233`), logs each `gh` call
  and runs the real `gh`.
- The other programs it runs are `git`, `gh`, `herdr` 0.9.2 or later (`bin/lib/agents.sh:174`),
  `claude`, `codex`, `python3`, `awk`, `sed`, `perl` (in 6 files) and `curl` (`bin/swarm.sh:141`),
  all found on `PATH`.
- State is files under `.swarm/` (`events.tsv`, `findings.tsv`, `agents.tsv`, `run-times.tsv` and
  more) and the board's markdown files. Eight lock functions guard it, among them `state_lock`
  (`bin/lib/board.sh:3108`) and `merge_lock` (`bin/lib/merge.sh:1081`). The code reads 126
  distinct `SWARM_*` names.
- The tests are 208 files, 55,278 lines of bash, run by `scripts/test.sh` under `make test`. CI
  runs them in 14 shards, all on `ubuntu-latest`; the last 5 runs on `main` took 5 min 36 s to
  5 min 58 s. They put stubs on `PATH`: 117 of the 208 files stub `gh`, 100 `herdr` and 88
  `claude`, and the stubs match on the calls made. Between 46 and 67 files reach inside the code:
  they source `bin/lib/*.sh`, run a `.py` helper, read the source text or stub `python3`. The
  range comes from two regex passes. 120 files call `python3` themselves. About 10 copy `bin/`
  into a temp folder as a plugin home (the reviewer's count).
- Claude Code delivers the plugin by copying `main` (`.claude-plugin/marketplace.json:9` is
  `"source": "./"`) into `~/.claude/plugins/cache/swarm-dev/swarm-dev/<version>/` and putting
  `bin/` on the Bash tool's `PATH`. The copy is not a git checkout. An update is for the whole
  machine. Older version folders stay for a while: on the lead's Mac the 6 folders from 0.30.0 to
  0.31.1 were still there on 2026-11-18. Claude Code's docs give 14 days.
- `.github/workflows/release.yml` publishes a tag and a release when a merge to `main` changes the
  version in `plugin.json`. It attaches no files and checks nothing out. `merge --release` takes a
  PR that changes only that version. It refuses a patch unless every change since the tag is from
  a `fix: true` story or a fix-main build (`bin/lib/board.sh:1586`), and a minor needs a done
  retro. Its docs gate looks only at `bin`, `commands` and `hooks` (`bin/lib/merge.sh:3009`).
- This board runs `merge = agent`: a story's review agent merges its PR. `merge` holds any PR that
  changes `.claude/`, `.github/`, `hooks/` or a root makefile for the user
  (`bin/lib/board.sh:2461`). `bin/lib/merge.sh` and the patch gate are under none of those.
- The board has 8 active epics and 6 ready lead stories, `status-speed-readings` among them.
- 31 lines in 7 files of AGENTS.md, `docs/` and `commands/` name `bin/lib/` or `bin/swarm.sh`.

## Design

Decided with the user on 2026-11-18 and, after the review, on 2026-11-19.

### Layers

The user asked that a later move to Kubernetes stays possible, and said on 2026-11-19:
"eventually we will probably not use herdr". So the packages that hold the rules (the board, the merge decisions, the lead's queue) never start a process or touch a file
themselves. They take four small interfaces:

- the agent runner, which is herdr today;
- the code host, which is `gh`;
- the repo, which is `git`;
- the store, which is `.swarm/` and the board's files.

v0.32 writes exactly one implementation of each, and a CI check fails an import that crosses the
line. Nothing shaped for Kubernetes is built.

### One binary behind today's names

One Go module at the repo root builds one binary: `go.mod`, with the entry under `cmd/` and the
packages under `internal/`. `bin/swarm.sh` stays as a short wrapper. It finds the binary for its
version and platform, gets it if it is missing, and runs it for a ported command. For a command
not yet ported it runs the bash as today. Each ported command is marked by a small file of its
own, so two port PRs never edit the same line. The hook files keep their paths and become
wrappers too, as does `bin/gh-shim/gh`. When the last bash is gone the wrappers only find the
binary and run it.

### How the binary reaches a machine

The release-ref spike tested each step of this section (§ Before this is agreed).

- `main`'s `marketplace.json` points the plugin's source at the stable ref, in the form
  `{"source": "url", "url": "<repo>", "ref": "stable"}`. A machine that already has swarm-dev
  follows it with no step of its user's. The release workflow moves the ref only after the
  release has its files, so an installed tree always matches a binary that exists. The version
  check (`bin/swarm.sh:128`) reads the same ref.
- There are two refs. Port patches move the prerelease ref. The stable ref, which every other
  machine installs, moves when a stage ends: the lead moves it once the user has cleared the
  stage's exit epic (§ Stages). To roll back, the ref is moved back and the sessions restarted,
  which rolls the hooks back too.
- The lead's machine runs the prerelease. A branch that never moves, `pre-marketplace`, holds a
  `marketplace.json` named `swarm-dev-pre` whose plugin source is the prerelease ref. The lead
  adds that marketplace, installs `swarm-dev@swarm-dev-pre` and uninstalls `swarm-dev@swarm-dev`.
  Every project on that machine then runs the prerelease.
- Switching between the two is a lead step, and it always uninstalls the other. With both
  enabled the plugin's hooks would load twice.
- `swarm.sh` reads the installed plugin's ID wherever it names the plugin: `update`, `upgrade`,
  and the dashboard's lookup of its own install (`bin/lib/dash.sh:552`). Today it names
  `swarm-dev@swarm-dev` (`bin/swarm.sh:129-130`).
- The release PR stays a version bump and nothing else. A required check on it builds the four
  binaries in a job with read-only permissions, so a version that cannot build never merges.
- After the merge the release workflow builds again in a read-only job. A second job publishes
  the binaries with their SHA-256 checksums and a GitHub build attestation, then moves the ref.
  No checksum is committed to git, so CI never commits to `main`.
- An installed copy downloads its binary on first run, and only with `gh release download`. The
  wrapper checks the SHA-256, then runs `gh attestation verify` against this repo, which shows
  the binary came from this repo's release workflow. It keeps the binary in the plugin's own
  folder. The write is atomic, so agents that start together are safe.
- The wrapper refuses to run a file that carries macOS's quarantine mark, with one line that says
  so. On the lead's Mac on 2026-11-19 a Go binary with that mark did not run: macOS showed "Apple
  could not verify" and the process hung until killed. Go's own ad-hoc signature was not enough.
  A binary fetched with `gh release download` carried no such mark and ran with no dialog, on
  that Mac and on the user's second one. Signing and notarising the macOS binaries is the fallback if a machine still
  refuses.
- Each release carries four platforms: darwin/arm64, darwin/amd64, linux/arm64 and linux/amd64.
- When the download or the checks cannot work (no network, another platform, a `gh` too old to
  verify an attestation), the wrapper builds from the source beside it if Go is installed, and
  says so. Otherwise it stops with one line that says why and what to do. It never falls back to
  old bash.
- A git checkout builds from source, into a path `.gitignore` names.

### The wrapper's contract

- One environment variable names a built binary. With it set, the wrapper runs that binary and
  never downloads or builds. `make test` builds once and sets it, so a copy of the tree with no
  `.git` still runs the code under test. A stage 1 test proves it: such a copy with broken Go goes
  red.
- A hook never downloads and never builds.
- A hook with no binary refuses a command that says merge, and every command the guard refuses
  today because it loses work (`git reset --hard`, a checkout over uncommitted changes and the
  rest), each with a line saying the guard cannot run. The rest pass. `lead-stop.sh` allows the
  stop. The user chose this on 2026-11-19: after Claude Code updates the plugin by itself, hooks
  run with no binary until a `swarm.sh` call fetches it, and the rules that keep work from being
  lost must not lapse in that window.
- The guard's bash fast path goes, so every Bash tool call starts the binary. On the lead's Mac
  on 2026-11-19 (load about 1.5, a binary fetched with `gh release download`, 20 starts each) a
  Go hello-world took 3.8 ms a start, `/bin/bash -c true` 3.4 ms and `python3 -c pass` 17.7 ms.
  The cost is the cold start: the first run took 0.46 s, so each update pays about half a second
  once.

### How a command is ported

1. Tests come first, in bash. A test-only PR rewrites the command's inside-reaching tests to drive
   `swarm.sh` from outside. It must pass against the bash, and each rewritten check is shown to
   fail when what it guards is broken.
2. Then the port PR adds the Go, deletes the bash and Python it replaces, and marks the command
   ported. It changes no file under `tests/` but the ones its story lists.
3. The port PR repeats the command's mutation proofs against the Go, since the tests were only
   shown able to fail against the bash. The brief says where to break.
4. The port PR corrects every doc line that names a file it deletes.
5. The differential run against the tree just before the port is clean (goal 2).
6. The reviewer reads the deleted bash against the Go, rule by rule, with the stage 1 inventory as
   the checklist. rules.md says a new code path must enforce every rule the old one did.

### Order

The 60 Python helpers go first. Each already runs as its own process and takes text, so swapping
one for the binary changes no bash structure, and `python3` goes early. The commands follow, by
who calls whom.

### Exceptions to one implementation

1. The three in-process bash helpers (front matter, config, event lines) keep their bash copy
   until the last bash caller is ported. Calling the binary for each read would start a process
   hundreds of times per command. A test runs the bash and the Go over every board file and config
   fixture and compares the output.
2. The wrapper's own rules: it reads the version from `plugin.json`, and a hook with no binary
   refuses a command that says merge or loses work.
3. A shared Python module (`report.py`, `events_outcome.py`, `clock.py`, `panes.py`,
   `touches_rows.py`) keeps its Python copy until its last Python importer is ported, under a test
   that runs both over the same input and compares the output. Each helper imports several of
   them, so no helper could be ported in one PR otherwise.

### Tests

- Stage 1 lists every inside-reaching test file and marks each "rewrite from outside" or "becomes
  a Go test". The user agrees the list. It replaces the 46 to 67 range.
- Stage 1 writes the inventory a reviewer checks a port against: the `SWARM_*` names, the lock
  files and their protocols, and the exit codes of each command.
- Stage 1 builds the differential run and the CI speed fixture (goals 2 and 7).
- CI gains one macOS job that runs the Go tests and a small subset of the bash tests, since two
  of the four binaries are for macOS and every job today is Linux.

### Protected paths

The first stage 1 story adds the Go packages for the guard, `merge`, the release gates and the
agents' environment to the protected paths, and the Go tree to the docs gate. It has a test that
a PR touching each is held. The user merges that story, the ports of those four, and every later
change to them. The user also merges the PR that changes the patch gate.

### Releases

- v0.32.0 is a minor, after its retro, and carries stage 1.
- v0.32.0 teaches the patch gate two more cases beside `fix: true`. A PR whose whole diff is
  under `tests/` passes. A `port: true` story's PR passes when its diff changes nothing under
  `tests/` but the files the story lists. The gate reads the diff as well as the flag. The change
  bumps the gate's rule version (`bin/lib/board.sh:1590`).
- After that the lead cuts a v0.32.x patch to the prerelease ref whenever ports have merged.
- The folded stories are `fix: true`.
- The docs gate works as today. A port PR that corrects doc lines satisfies it; one with none to
  correct says `Docs: none` with the reason.

### Folded work

Each item is its own `fix: true` story on the Go code, right after its command's port, with its
own test. For the 12 stories, the story's **Done when** is the requirement. The 12 story files
still say "Python rewrite" and have no `fix:` or `epic:`; the plan rewrites each.

| Command | Folded stories | Deferred on 2026-11-18 |
|---|---|---|
| `merge` | [merge-refuse-red-base](../stories/merge-refuse-red-base.md), [protected-hold-grant](../stories/protected-hold-grant.md) | none: `dropped-lines` skipping a story PR's own story file (3 of the 8 v0.31.2 PRs were held by it) is fixed in bash before the freeze, as [dropped-lines-own-story-file](../stories/dropped-lines-own-story-file.md) |
| `next` | [next-origin-tags](../stories/next-origin-tags.md), [next-starts-gaps](../stories/next-starts-gaps.md) | |
| `story` | [board-worktree-guard](../stories/board-worktree-guard.md) | |
| `wait --lead` and the lead's stop hook | [lead-stop-wakes](../stories/lead-stop-wakes.md), [lead-queue-failed-read](../stories/lead-queue-failed-read.md) | no `conflict:` line while GitHub is still working out whether a PR merges (2 of 2 such lines that day were false); a builder left idle on an ended background run with uncommitted edits is noticed |
| agent starts and notes | [name-clash-all-starts](../stories/name-clash-all-starts.md), [note-sender-header](../stories/note-sender-header.md), [calls-with-deadlines](../stories/calls-with-deadlines.md) | |
| `retro` | [retro-local-day](../stories/retro-local-day.md) | |
| `review-agent` | [fail-line-check](../stories/fail-line-check.md) | the first start right after a PR opens is not refused because the worktree is one commit ahead (3 PRs that day) |

### Go rules

- Standard library only. `go.sum` stays empty, and the Go toolchain is pinned in `go.mod`. The front matter and config parsers are our own
  and match the bash line for line.
- CI requires `gofmt`, `go vet`, `staticcheck` and `errcheck`. Every error is handled or returned.
- Time is read through one clock package, as `bin/lib/clock.py` does today, and a CI check fails
  a time read anywhere else. Sleeps keep `SWARM_SLEEP_SCALE`.
- `git`, `gh`, `herdr`, `claude` and `codex` stay subprocesses found on `PATH`, so the tests'
  stubs keep working.
- The Go takes the same lock files in the same way as the bash. Sessions on an older version share
  the project's `.swarm/` until they restart.
- The wrappers still run on macOS's bash 3.2.

### Freeze

The freeze starts when the first port story starts. Before that, each of the 8 active epics is
finished or closed, and the user clears or drops the 6 ready lead stories. From then until the
bash is gone, `main` takes only port stories, their test rewrites, `fix: true` stories and
fix-main builds. A fix to a command still in bash lands in bash with its test, and the port
inherits the test. Nothing in the code enforces the freeze. The lead holds it when it plans, and
the patch gate refuses a patch that carries anything else.

### Stages

Each stage ends on an exit epic holding one `kind: lead` story. The exit epic depends on every
other epic of its stage, and the next stage's epics depend on the exit epic. In the exit story the
user runs the new version on their machines, reads the stage's differential run against v0.31.2 and
the CI speed figures, and says go. The lead then moves the stable ref. Under the `epics` grant
every epic goes active at plan time, but each stage's epics name the previous stage's exit epic
in `depends_on`. The exit epic is written by the same plan PR, so it exists from the start, and an
open epic holds its dependants' planning until every story in it is done or in review (`dep_holds`,
`bin/lib/board.sh`). The exit story has no PR, so it never goes to review: it goes from ready to
done only when the user says go, and the lead marks it done in a board PR. A dependency on the exit story itself would not hold: that story does not
exist until the exit epic is planned, and a slug that names nothing counts as met. So none of a
later stage's epics is planned into stories or built until the user has said go at that exit.

| Stage | Ships as | Contents |
|---|---|---|
| 1. Foundation | v0.32.0 | The wider protected paths, first. The Go module and its CI checks, with the macOS job. The wrapper and its contract. The build check on the release PR, the two-job release workflow with its checksums and attestation, and the two release refs with the `pre-marketplace` branch. `swarm.sh` reads the installed plugin's ID. The patch gate's two new cases. The test selector learns the Go files. The four interfaces and the import check. The list of inside-reaching tests, the inventory, the differential run and the speed fixture. One Python helper replaced end to end, through to a release on the prerelease ref. |
| 2. Helpers and readers | v0.32.x | The 60 Python helpers. Then the commands that change nothing: `status`, `next`, `dash`, `flow`, `outcomes`, `retro`, `dataset`, `config`, `policy`, `grants`, `where`, `swarms`, `findings`. |
| 3. The loop | v0.32.x | `wait` in all its forms, `wait-pr`, `watch`, `merge`, `review`, `reconcile`, `conduct`, `story`, `agent`, `review-agent`, `codex-review`, `tell`, `close`, `step-up`, `restart`, `upgrade` and the remaining writers. Then the 5 hooks and the gh shim. |
| 4. Retire | last v0.32.x | The three in-process helpers and their comparison test. What bash and Python is left under `bin/` and `hooks/` but the wrappers. The README drops `python3`. The shellcheck list and CI's Python step follow. |

## Alternatives

- Python was the first choice, on 2026-11-17. The user changed to Go on 2026-11-18 for one fast
  binary with no interpreter to start, and type checks at compile time.
- New code could go in Go while the old code is left alone, with no rewrite to plan. The user's
  answer was that it only gets worse.
- The slow commands could be measured and fixed in bash, with no rewrite. The `status-speed` epic
  does that and finishes before the freeze. It leaves the two languages as they are.
- The rewrite could be one big branch, released once. The patch gate would block every loop fix
  until it landed, and the swarm would never run the Go code while building it.
- Each command's bash could stay behind a switch until the end, which makes rollback take
  seconds. But commands still in bash call each other's functions, so a ported rule would have
  two live versions, and the frozen bash would miss every later fix.
- The shared helpers could be ported first with no bash copy, as the first draft had it. Every
  command still in bash would then start a process per board read.
- The inside-reaching tests could change in the port PR, or be replaced with Go tests. That needs
  fewer PRs, but the test and the code change together, so a weakened test looks like a faithful
  one.
- Each user could add the marketplace again at the stable ref. That is a step of theirs, and
  anyone who missed it would keep getting `main`.
- `main` itself could be the stable ref, with the work on another branch. Existing installs
  would follow it untouched, but every PR base, the CI triggers and the board's base branch
  would move, and the release would again have to reach `main` before its binaries exist.
- The marketplace could keep installing from `main`. A new version would then reach users before
  its binary exists, and a fresh install between releases would get `main`'s ported-command
  markers with the last tag's binary.
- The binaries could be committed to a `dist` branch the marketplace installs from, with no
  download step. The branch grows with every release.
- Every machine could build from source, with nothing to publish or verify. Every user would
  need Go. It stays as the fallback.
- The binaries could be committed to `main`. That adds tens of MB per release, and there were 29
  version tags in the five weeks to 2026-11-18.
- The release PR could carry a checksums file in git, as an earlier draft had it. That needs
  builds that are byte-identical on macOS and in CI, or CI committing to `main`, which the
  ruleset and commit signing forbid. The user chose to design around it.
- The wrapper could check the release's checksum alone. That only catches a corrupt download,
  since whoever replaces the binary can replace the checksum.
- The macOS binaries could be signed and notarised from the start. That needs an Apple developer
  account and its secrets in CI. It stays as the fallback.
- The wrapper could download with `curl`. `gh` is already required and logged in, and it handles
  proxies and private forks.
- Every machine could get every patch. A bad port of a loop command would then stall the user's
  other boards and other users' swarms.
- Ports could be marked `fix: true`, with no gate change. But a port is not a fix, and `flow`
  would count it as one.
- Each stage could be a minor. That means four retros, and the UI moves to v0.36.
- The stages could have nothing between them. They sit inside one minor with no tag to separate
  them, so the loop could then be ported before stage 1 had proved the build.
- The HLD could carry all four grants. `merge` and `release` are read only under `merge = human`,
  so here they would only keep PRs merging and patches shipping after the user flipped that
  setting to stop a bad run.
- The user could agree each epic through `/epic`. The plan has about 50 epics, and the stage
  exits already give the user a stop before each stage starts.
- The port could make commands faster as it goes. The stubbed tests would then change with the
  port, which gives up the unchanged-tests check.
- A few vetted libraries would mean less code. They also mean more supply chain to watch, and a
  real YAML parser may read a board file differently from today's bash.
- Each behaviour change could go inside its port PR. That needs fewer PRs, but a reviewer must
  then tell port mistakes from intended changes.

## Risks and safety

- The swarm rebuilds what it runs on. A bad port of a loop command can stall the swarm that would
  fix it. Helpers and readers go first, each port is small, and only the lead's machine runs a port
  before its stage ends. The user's other boards on that machine run it too. To roll back, the lead moves the prerelease ref back and restarts the sessions.
  docs/lead-by-hand.md lists the steps the lead can still take by hand.
- Only v0.32.0 has a retro, so the loop's ports ship without one. The stage exit epics are
  where the user looks before the loop starts and before it reaches other machines.
- Behaviour that no test pins can be lost unseen. The differential run, the inventory and the
  reviewer's reading of the deleted bash are the three checks on it.
- Two of the ports are safety checks. The guard hook refuses raw merges and commands that lose
  work. `merge` pins the head and holds PRs for money, protected paths and dropped lines. The
  user merges both (§ Protected paths).
- Many PRs wait on the user: every PR that changes `.github/`, `hooks/`, a root makefile or one
  of the four protected Go packages. The co-author's guess is 20 to 30 PRs. The plan gives the
  real number.
- Sessions on different versions share one `.swarm/`. Hooks load only when a session starts, so
  an old session keeps bash while a new one runs Go. Both take the same locks and append to the
  same logs, which is why the lock protocols may not change.
- The binary comes from the network. The attestation ties it to this repo's release workflow,
  and the wrapper checks it. The publish job gains the permissions an attestation needs; the
  build job stays read-only, and the actions stay pinned by SHA. A managed machine may still
  refuse to run an unsigned binary. Both of the user's Macs ran one.
- First run needs the network, once per version per machine.
- A machine with both `swarm-dev@swarm-dev` and `swarm-dev@swarm-dev-pre` enabled loads the
  hooks twice. Only the lead's machine ever has the second, and the switch uninstalls the first.
- The agents' environment allowlist (`AGENT_ENV`, `bin/lib/agents.sh:388`) must carry over
  exactly. Its test is one of those rewritten first, and its Go package is protected.
- CI gains a Go build in each of the 14 shards, one lint job and one macOS job. GitHub's docs say
  standard runners are free for a public repo; that is not checked against this repo's bill. No
  LLM cost is added.
- Local test runs gain one compile. The caps in AGENTS.md stay.
- Nothing a board sets is removed: no setting, field or brief form goes. `port: true` is added.
- The work touches no cloud and no credentials. It costs nothing beyond the swarm's own model
  usage, which is not estimated here.
- The lead's estimate was 40 to 45 stories. With the test rewrites, the 16 folded items, the
  Python helpers as their own step and the stage 1 tooling, the co-author's guess is 80 to 100.
  The plan gives the real number.

### Grants

Set by the user on 2026-11-19: `stories` after the review, then `epics` once the plan came to
about 50 epics.

- `epics`: /plan-hld writes the epics `active` and opens the board PR without asking. Each
  stage's epics depend on the previous stage's exit epic (§ Stages), so nothing in a later stage
  is planned or built before the user says go at the earlier stage's exit.
- `stories`: /plan-epic writes each epic's stories and opens the board PR without asking. At 80
  to 100 stories the user cannot read each one.
- The carve-out: the board PR lists for the user any story that touches the guard, `merge` or the
  release gates, or names `env:`, and waits for the user's go on those. The reason is that those
  stories change what checks a merge or ship, and `env:` hands an agent a variable. The user
  narrowed it on 2026-11-19: after stage 1 nearly every story sets `fix:` or `port:`, so listing
  those would have stopped on about 220 stories. Nothing in the code enforces the carve-out. The
  lead holds it, and the user clears each listed story by agreeing it on the board PR.
- `merge` and `release` are not carried. `merge` and
  `release` are read only under `merge = human`, so on this board they would do nothing but keep
  PRs merging and patches shipping after the user flipped that setting to stop a bad run.

## Rollout

- Before this is agreed: the spikes below, all answered on 2026-11-19.
- Before the first port story: the 8 active epics are finished or closed and the 6 ready lead
  stories cleared.
- Before v0.32.0: its retro, as the retro gate asks. It records that the test-speed work the
  v0.31.0 retro sent to v0.32 (the git wrapper's cost, lazy-loading of libs, a fake clock, shared
  fixtures) moves to v0.33 (the user, 2026-11-19).
- The stages follow in the order of § Stages. Every port can ship to the prerelease ref on its
  own.
- Each stage ends on its exit epic. For its exit story the lead records the differential run against
  v0.31.2, the CI fixture's wall time and process starts per command, and the lines of bash and
  Python and the `python3` calls that are left. Once the user says go, the lead moves the stable
  ref. At the end of stage 4 those three counts are zero outside the wrappers and `scripts/`.
- The Go checks and the release PR's build check join the required checks on `main`. Changing
  the ruleset is the user's step.

### Before this is agreed

Each item has an answer written here before the user agrees the HLD. A spike on byte-identical
builds was dropped on 2026-11-19 when the checksums left git.

The release-ref spike is answered (the lead, 2026-11-19, in a throwaway `CLAUDE_CONFIG_DIR`, the
last two points against a throwaway private copy of the repo):

- Claude Code installs from a ref. A marketplace added as
  `https://github.com/redscaresu/swarm-dev.git#v0.31.1` installed 0.31.1 while `main` was at
  0.31.2.
- An update follows a branch ref after it moves. With the marketplace on `#stable` at 0.31.2,
  the branch was moved to a commit at 0.31.3, and `claude plugin marketplace update` then
  `claude plugin update` printed "updated from 0.31.2 to 0.31.3".
- An existing install reaches the stable ref with no step of its user's. A marketplace added
  the way users add it today, with `main` at 0.31.1, was updated to 0.31.2 once `main`'s
  `marketplace.json` pointed the plugin's source at `stable`, while `main`'s own `plugin.json`
  still said 0.31.1. Moving `stable` to 0.31.3 updated it again.
- One project cannot run a different ref from the rest of the machine. Adding the same
  marketplace again with `--scope project` and another ref failed: "its source doesn't match its
  extraKnownMarketplaces entry in user or managed settings". So the prerelease goes to the lead's
  whole machine.
- A second marketplace name carries the prerelease. With `stable` at 0.31.2 and `prerelease` at
  0.31.3, adding `<repo>#pre-marketplace` beside the first marketplace and installing
  `swarm-dev@swarm-dev-pre` gave 0.31.3. Both plugins then stood installed and enabled at once,
  until `claude plugin uninstall swarm-dev@swarm-dev` left only the prerelease one. Moving
  `prerelease` to 0.31.4 updated it; moving `stable` to 0.31.9 left it at 0.31.4.
- Not tested: `swarm.sh update` and `upgrade` against the second name. They name the plugin's ID
  in the code today, which is why the design has them read it.

The machine spike is answered, on both of the user's Macs (2026-11-19, from the prerelease
`spike-go-binary-2026-11-19` the user created):

- A Go binary fetched with `gh release download` carried only `com.apple.provenance`, with no
  quarantine mark, and ran with no dialog on both.
- The first run took 0.46 s on the lead's Mac and 0.52 s on the second, where it used almost no
  CPU. Later runs took about 4 ms.
- So neither machine needs a signed binary. Signing and notarising stays the fallback.

## Open questions

1. Under `merge = human` with a `merge` grant, is a protected-path PR held today? The folded
   story says no (#661, #595). The code's comment says such a PR is under no HLD
   (`bin/lib/board.sh:2457`). The protected-hold-grant story finds out with a fixture and holds it
   either way.
2. Where does `status` spend its time? The `status-speed` epic answers it before the freeze, for
   v0.33 to use.
3. What notices a builder left idle on an ended background run? The requirement is in § Folded
   work. Its story settles the shape, and the user agrees it there.
4. Can the lead's other boards stay on stable while this repo runs the prerelease? Both plugins
   can be installed at once, but nobody has tried enabling one per project. Until someone does,
   the whole machine runs the prerelease. The lead may try it in stage 1.

## Epics

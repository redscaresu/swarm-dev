# Running swarm-dev: the details

*For v0.30.0.* The [README](../README.md) is the short introduction. This page holds the detail for
someone already running a swarm: each step of a run, every stop and what to do, the commands for
watching it, the safety rules, updating, and the test tooling. The full rules, settings and logs are
in the [reference](reference.md).

## Each step of a run

1. **Write the work.** `/swarm-dev:hld <title>` opens a co-author agent in its own pane. Together
   you write the high-level design (HLD): a release's worth of work, and the `grants:` that say
   what the swarm may do under it without asking you. A reviewer agent attacks the draft. Once you
   agree it, `/plan-hld` splits it into epics. You agree each epic with `/swarm-dev:epic <title>`,
   which also writes a single epic from scratch: the problem and its evidence, goals that can be
   checked (**Done when**), what is out of scope, and your part. Nothing is planned until you
   agree it. `swarm.sh board-pr` refuses a board PR that sets an epic `active` without your
   agreement, a parent epic, an HLD that grants `epics`, or `lead_epics = on`.
2. **Plan.** `/swarm-dev:swarm` splits the agreed epic into stories of one PR each. A survey agent
   reads the code, a lead agent writes the stories, and skeptic agents (on risky stories only), codex and a critic try to
   refute them. You approve the result, which is then written to the board. An epic too large for
   one run is split into smaller epics first.
3. **Build.** A conductor agent starts one builder per story. Each builder works in its own git
   worktree and opens a PR. When the PR opens, the conductor starts a review agent for it, and from
   then on the PR is that agent's: the conductor never reviews or merges it. Once CI is green, the
   review agent and codex review the PR, and the builder fixes what they find. When a review finds
   nothing left to fix, the review agent merges the PR or hands it to you (step 4). A story that fails twice is rebuilt once on Fable, the most capable model,
   then handed to the lead. One story waits for another only when they clash: their `touches`
   name the same file in the same repo, and either the same part or both the bare file. Parts match
   on their first word (a function or section name), skipping a leading `§`, `#`, "the", "a" or
   "an". A bare file does not clash with a part of that file.
4. **Merge.** By default you merge each green, reviewed PR yourself. The lead, or the PR's review
   agent, merges one only when the agreed HLD over its work lists `merge` in its `grants:`.
   With `merge = agent`, the review agent merges it, except a story marked `costs: money` and a story PR
   that changes `.claude/`, `.github/`, `hooks/` or a root `Makefile`, which always wait for you.
   In that mode no conductor starts until your Claude Code settings allow
   `swarm.sh merge` (step 3 of Getting started names the rule). `swarm.sh conduct` prints the rule
   to add, and so does `swarm.sh next` while it waits on a working conductor. After a merge, main is
   judged by the checks it requires, and any other red check prints a `warning:` line. A required
   check that fails in GitHub Actions is rerun once; if it passes then, merge prints a `flaky:`
   line. If main is still red, the swarm writes a story to fix it and builds that first.

Your own Claude session is the lead. It runs `/swarm-dev:swarm`, watches the agents, and does the
stories no agent may: real cloud, credentials and anything hard to undo. Your steps in those are
marked **You:**.
It makes the routine calls without asking you: restarting a stuck agent, starting reviews and conductors, throttling load, and a `--force-with-lease` push to a story branch once the PR's diff is unchanged and every commit is signed.
It logs each one with `swarm.sh intervene`, and still asks you about held merges, **You:** steps, money, credentials and your own settings files ([the lead's rules](../commands/swarm.md)).
The board is plain Markdown in your repo, so a run can stop anywhere and the next
`/swarm-dev:swarm` picks up where it left off.

## Every stop, and what to do

| You see | Do |
|---|---|
| a draft HLD | finish it with the co-author, then agree it; its `grants:` are yours to set |
| proposed epics | agree each with `/swarm-dev:epic`, or say what to change |
| a draft epic | finish it with the co-author, then agree it |
| a draft epic the lead sets active (`draft epic: <slug>, the lead sets it active (<why>)`) | nothing: its `parent:` is active or split, an agreed HLD over it grants `epics`, or `lead_epics = on`, so the lead sets it active in a board PR |
| a staged epic (`staged epic: <slug>, stage v<T>, after v<P>`) | nothing: once the base has a tag at or above `v<P>`, the lead sets it active in a board PR, which you merge unless `merge = agent` or the HLD grants `merge`. Leave that PR unmerged to say not yet. To take an epic out of its stage, drop its `stage:` or `hld:` |
| proposed stories | approve them, or say what to change |
| a `lead` story | say go, and do its **You:** steps |
| a PR waiting for you | merge it, ask the lead to, or close it to send the story back; one under an HLD that grants `merge` the lead lands itself |
| a retro before a minor release (`retro v<x.y.z>`) | do the `retro-v<x-y-z>` lead story's **You:** steps with the lead: pick the version, decide what becomes of each item `swarm.sh retro` lists, and land `retros/v<version>.md` by board PR. Then `next` offers `release v<version>` |
| a `blocked` or `later` item | nothing, or set it `ready` / `active` to start it. For a `later` epic, say go and the lead sets it `active` with `agreed: <today>` |
| an agent's login expired | run `/login`, then tell `/swarm-dev:swarm` it's done |
| an agent waiting on a prompt or a dialog, or in manual mode | answer the prompt in the pane the lead names, or turn manual mode off there. The lead hears of most within a poll. Manual mode turned on, or a dialog opened, at an idle box can take up to 5 minutes, and a slow pane read ahead of it can add a poll. A ready story's builder in manual mode it handles itself: it closes the pane, then restarts or holds the story |
| an agent stuck | read its pane (`herdr agent read <agent>`), then type into it or close it (`swarm.sh close <agent>` keeps its open PR and puts the story in review with it; add `--drop` to close the PR and build the story again) |

## Watching a run

| Command | What it shows |
|---|---|
| `swarm.sh status` | First, a No agent section for any story whose build started but has no agent working on it, or whose PR's review agent never started or went, each with the command that fixes it. Then agents that need a look, each with its pane, workspace and tab, what waits on you, and what runs next, with any `idle:` lines `next` prints for blocked stories, ready stories with no build, epics that can start and active epics with no plan running. |
| `swarm.sh where <agent>` | Which workspace and tab one of this project's agents is in, and its pane id. `<agent>` is a story's slug, `review-<slug>`, `conduct-<epic>` or the agent's herdr name. |
| `swarm.sh swarms` | Every swarm running on this machine, whichever project you run it from: each `swarm-lead · <project>` workspace with the folder its lead runs in, then that project's other workspaces with their agents. |
| `swarm.sh flow` | Cost, CI health and the flaky tests, where stories spent their time (including how long a ready story waited for its build, how long a green PR waited for its next review round, and how long ready work sat with no build while its conductor ran), how each model did, how well the planner guessed which stories were easy and how big, what each review round found, which agents spend GitHub's API budget, and how long local `make test` runs take by how many ran at once. Finished GitHub history is cached in `.swarm/gh-cache/`, so a second run asks GitHub only for what is open or new (`--no-cache` reads it all again). |

`swarm.sh status` gives its herdr, gh and claude reads, each agent's pane read included, and its git fetch and ls-remote, 30 seconds in all, and a last `skipped (over 30 s): ...` line names any read it cut.
The Stacked, Waiting on you and Next sections start only before that deadline.
One due past it is skipped: its heading says `skipped (over 30 s)`, and the last line names it after the cut reads.
A section that started in time finishes.
To see where a slow `swarm.sh status` run spends its time, run `SWARM_REPORT_TIMES=1 swarm.sh status`.
It writes one `time: <section> <seconds>` line to stderr per section, in order (no-agent, agents, stacked, waiting, next, idle), then `time: total <seconds>`.
Stdout does not change.

The other commands are ones the lead runs. [reference.md § Commands](reference.md#commands)
links to the Commands section at the end of each reference file.

## Workspace labels

Every herdr workspace swarm.sh opens for a conductor or the lead's agents, and the lead's own, is
labelled with its project:

- `swarm-lead · <project>`: the lead's own workspace and tab, relabelled by the first swarm.sh
  command the lead runs there after `swarm.sh init` (any but `version` and `update`).
- `<project> · <epic>`: an epic's conductor and its builders.
- `<project> · backlog`: the backlog conductor and the one-off stories it builds.
- `<project> · lead-agents`: the agents the lead starts itself, such as the HLD co-author or a
  planner, so they stay out of the lead's own workspace.

`<project>` is the project folder's name, with a short hash of its path after it when another folder
of the same name already has a workspace. A conductor reuses a workspace only when its panes say it
is this project's. Two folders of the same name can still get the same label, for example when
both start a conductor at the same moment, when one sits in a folder whose name ends in `-wt`, or
when one's workspace has only its builders left
([reference-building.md § Building](reference-building.md#building)).

## Cost and safety

Every agent is a full Claude Code session on your own logins, so a run spends real tokens. On one
project a story's build averaged $5.75, or about $9 per merged PR with planning and review
included, at list prices. `swarm.sh flow` shows where your own tokens went.

- No agent touches real cloud or credentials. That work is a `lead` story, done in your session
  while you watch.
- Agents start with a short list of environment variables. Any other variable you exported reaches
  an agent only when its story names it under `env:` or the board's config lists it in `agent_env`.
  With Foundry on, its `ANTHROPIC_FOUNDRY_*` and model settings pass to every agent too. With Bedrock
  on, so do its `AWS_BEARER_TOKEN_BEDROCK` key and model settings. On a Claude subscription there
  is nothing to pass: agents use your logins through `HOME`. On Bedrock, `AWS_ACCESS_KEY_ID`,
  `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN` pass only when a story's `env:` or the board's `agent_env` names them; a profile
  or SSO login reaches agents through `HOME` and `AWS_PROFILE`.
- In a swarm project, a plugin hook guards every Claude session. It refuses raw PR merges (merges
  go through `swarm.sh merge`), a `git checkout` that would drop changes, a `git reset --hard`,
  `restore` or `clean` that would drop uncommitted work in the main checkout, an agent's `pkill`, and an agent's
  `make test` with no `TESTS=` in a checkout that has `scripts/select-tests.sh` (it points the agent
  at `scripts/select-tests.sh --run`).
- Nothing merges until you say so, unless you set `merge = agent`, or the agreed HLD over the work
  lists `merge` in its `grants:`, which only you set. `swarm.sh grants <PR URL>` shows the HLD and
  its grants. `swarm.sh merge` reads the grant at the head it merges, and refuses if a push has moved
  the head. Under `merge = human`, the lead merges a release only when every story merged since
  the last tag is under an agreed HLD that lists `release`.
  `swarm.sh merge --release` refuses, under either mode, a minor release with no done retro file for it, and a patch with a change since the tag that is not a fix ([reference-merging.md § The retro gate](reference-merging.md#the-retro-gate)).
  Under either mode, a PR that changes
  `.claude/`, `.github/`, `hooks/` or a root `Makefile` waits for you to merge it by hand. So does a
  PR whose own merge of the base dropped a line of the base that its head has not put back, or whose
  merges `swarm.sh merge` cannot check.
- Under either merge mode, `swarm.sh merge --board` refuses the same board PRs as
  `swarm.sh board-pr open`, and a plain `swarm.sh merge` refuses a story PR that sets an epic
  `active` with no ticket in the same way ([reference-merging.md § Merging](reference-merging.md#merging)).
- Unless a story PR joins a merge queue (it never does under `merge_admin = on`), `swarm.sh merge`
  does not merge a head that lacks commits on the base that change more than board files. It has
  GitHub merge the base into the PR's branch and checks that the new head adds only the base's
  commits. Then it waits up to 30 minutes for the new head's CI and merges that head, so the merge
  takes longer.
  If the base moves again during the wait, it does all this again, for 3 rounds at most. When GitHub cannot merge
  the base in (a conflict, say), the builder does, and the new head is reviewed before it merges
  ([reference-merging.md § Merging](reference-merging.md#merging)).
- Only a plan or agreement board PR gets a codex review. A board PR that edits a story's scope,
  holds a story or finishes an item lands on green CI alone. `swarm.sh board-pr open` prints the
  PR's kind ([reference-lead.md § The lead](reference-lead.md#the-lead)).

Settings live in `.claude/swarm/config`; [reference-models.md § Settings](reference-models.md#settings)
lists them all.

## First run

An installed copy of swarm-dev has no `swarm` binary until its first `swarm.sh` call fetches one.
Every call does this except `swarm.sh update`, inside a project or not.
`swarm.sh update` fetches nothing for the running copy.
It runs the newly installed copy's `swarm.sh version`, which fetches that copy's binary.
Each version fetches its own binary once:

1. `gh release download` fetches the release's binary for this machine, and its `SHA256SUMS`, into a new `.fetch-<pid>` folder in the plugin folder.
2. swarm.sh checks the binary's SHA-256 against its line in `SHA256SUMS`.
3. `gh attestation verify` checks that swarm-dev's release workflow built it.
4. swarm.sh moves the binary to `swarm` in the plugin folder, then removes the `.fetch-<pid>` folder.

Later calls find `swarm` there and check nothing again, except on macOS, where every call checks it for the quarantine mark.
The fetch runs the real `gh`, past swarm-dev's gh-shim, and needs gh 2.57.0 or newer, logged in.
A git checkout of swarm-dev never fetches: it builds the binary from its own tree.
With `SWARMDEV_BIN` set, swarm.sh runs that file and fetches nothing.

When the download cannot work here (no binary for this platform, no gh, a gh older than 2.57.0, or a failed `gh release download`), a machine with Go builds the binary from source instead, as [Offline](#offline) says.
Otherwise, or when that build fails too, the call stops with one line that starts `binary:`, and the command does not run.
`swarm.sh version` is the exception: it prints that line after its version line, and goes on.
What each line means:

- `swarm-dev publishes no binary for <os>/<arch>`: build one with `go build ./cmd/swarm` and set `SWARMDEV_BIN` to its path.
- `gh is not on PATH`: install the GitHub CLI and run `gh auth login`.
- `gh <version> is older than 2.57.0`, or `gh --version's first line ... is not 'gh version X.Y.Z'`: upgrade gh. Nothing was downloaded.
- `gh release download ... failed`: the line quotes gh. Fix what it says (no network, or no login), then run the command again.
- `gh attestation verify failed`, with `(no answer within 60 s)` when gh did not answer: check that gh is 2.57.0 or newer, logged in and online.
- `the SHA-256 of ... does not match`: the file is not the one the release lists, so it was not installed. Run the command again, and report it if it fails the same way.
- `has no line naming`, `names ... on <n> lines`, `left no`, or `holds <n> of the asset files`: the release is not laid out as swarm-dev expects. Run the command again, and report it if it fails the same way.
- `could not take the SHA-256`: install `sha256sum` or `shasum`.
- `cannot tell which release files are this copy's binary`, `cannot read this copy's version`, or a line about `--list`: the plugin folder is broken. Reinstall swarm-dev.
- `could not make` or `could not move`: the plugin folder is not writable.
- `is a folder`: something left a folder named `swarm` in the plugin folder. Remove it.
- `carries macOS's quarantine mark`: macOS puts this mark on a file that a browser, AirDrop or a mail app writes, and swarm.sh will not run a binary that has it. It checks the download, and on every call it checks the `swarm` file in the plugin folder, as copying the plugin folder can add the mark later. Delete that `swarm` file and run the command again: the call downloads and checks a new copy. If the download itself had the mark, run the command again, and report it if it fails the same way. A line that says `/usr/bin/xattr is not an executable file`, or that it `could not list the extended attributes`, means swarm.sh could not check for the mark, so it did not run the binary.

A fetch stopped by Ctrl-C or a TERM removes its `.fetch-<pid>` folder.
A KILL leaves the folder with the downloaded files in it, none of them executable.
No call runs them, the next call fetches again, and you can delete the folder.
Two calls at once each fetch into a folder of their own, then move a checked binary into place, so both run a whole binary.

## Offline

With no network, an installed copy's first call cannot download its binary.
If Go is installed, it builds the binary from the source in the plugin folder instead, prints one line, `binary: built from source, as <why the download could not work>`, and the command runs.
It builds the same way whenever the download cannot work here: no binary for this platform, no gh, a gh older than 2.57.0, or a failed `gh release download`.
The build needs the Go version that the plugin's go.mod names, or newer.
An older Go fetches that version itself, which needs the network.
If Go is missing or the build fails, the call stops with one `binary:` line, then any error Go printed, and the command does not run.
The line names why the download could not work, the Go version go.mod names, and why the build failed.
A download that fails a check (a wrong SHA-256, or a failed attestation) never builds, whether or not Go is installed: the call stops with the check's line.
A build that is stopped part way leaves no `swarm`.
It can leave a `swarm.build-<pid>` file in the plugin folder, which no call runs; the next call builds again, and you can delete the file.
Once the binary is there, a call needs no network to find it.
`swarm.sh version` and `swarm.sh update` never need the binary, so they still run.
`swarm.sh version` still tries the download and the build, and prints their `binary:` lines after its version line.
`swarm.sh update` does the same for the new version: it runs that copy's `swarm.sh version` once, which tries the download and the build for that copy.

## Updating

When the lead merges a swarm-dev release with `swarm.sh merge --release`, it updates the plugin.
It starts `swarm.sh upgrade` for the running agents only once you agree. The lead asks you before
the merge and passes `--upgrade` when you say yes; run by hand on a terminal, merge asks
`Move the running agents onto v<new> now? [y/N]` itself. With no terminal and no `--upgrade`, it
moves no agent and prints `upgrade not run:` with the command to run in each project. Either way,
it then asks you to restart the lead session (`/exit`, then `claude --continue`). If a PR landed on the base after the release was
checked, it names the commits that shipped unchecked and updates nothing. In that case, or when
you release some other way, run `swarm.sh update`.

`swarm.sh update` updates the plugin ID this copy is installed as.
For a stable install it runs:

```bash
claude plugin marketplace update swarm-dev && claude plugin update swarm-dev@swarm-dev
```

For a prerelease install it runs:

```bash
claude plugin marketplace update swarm-dev-pre && claude plugin update swarm-dev@swarm-dev-pre
```

Then it runs the new version's `swarm.sh version` once, within 5 minutes, and shows its output.
That fetches the new version's binary, as [First run](#first-run) describes, or builds it, as [Offline](#offline) describes, before your next session starts.
It finds the new version in Claude Code's `installed_plugins.json`, by the one user entry for the plugin ID.
When it cannot find it there, or that run fails or takes longer than 5 minutes, it prints one line saying the new version's binary was not fetched and that `swarm.sh version` after the restart fetches it.
It still exits 0.
Restart Claude Code afterwards.

After a plain `claude plugin update`, run `swarm.sh version` yourself once Claude Code has restarted.
When it can neither fetch nor build the binary, it says why after its version line, in one line that starts `binary:` and then any error Go printed, and still exits 0.
The next `swarm.sh` call tries again.

Agents already running stay on the old version until
`swarm.sh upgrade <epic>` restarts them on the new one, each resuming its own session. A builder
waits while the Claude review agent reviewing its PR is busy and still on the old version. upgrade
runs detached until every agent is moved, and prints its log, `.swarm/upgrade-<version>.log`.

swarm-dev's rules, [rules.md](../rules.md), ship with the plugin, so a project gets new rules with
`claude plugin update`. They reach the agents started after the update. `swarm.sh upgrade` resumes
each running agent's own session and sends it no new brief, so a resumed agent keeps the rules it
started with.

An epic with `stage: v<x.y.z>` holds its release. Until every epic of that stage has left the board,
`next` prints a `release-held:` line and offers at most a patch.
Then it prints `retro v<x.y.z>` until the stage's retro file is done, and `release v<x.y.z>` after that.

Upgrading to 0.27: an HLD that was split into epics before 0.27 has no `planned:` line. Once its
epics leave the board, `next` offers to plan it again. Add `planned: <date>` to its front matter
by hand.

On a board inside the project's repo, an agreed HLD must end with a line that is exactly
`## Epics`, followed only by blank lines and links `- [<slug>](../epics/<slug>.md)` to epics on the
board. `next` offers no `/plan-hld` for any other HLD, and the gate says what to change.

On a board outside the project's repo, `/plan-hld` writes epics in place. If a run stops part way,
`next` offers `/plan-hld <hld>` again, and the rerun overwrites the epics that run wrote. Once work
starts on one of those epics, `next` stops offering it.

## Test tooling

- `make test` stops a test file that runs past `TEST_FILE_TIMEOUT` seconds (600 unless set, three times that for the files in `SLOW`) and fails it as
  `TIMEOUT <file> after <n>s`, with the file's last 20 lines of output. It also adds a `reap` line naming the file to `.swarm/events.tsv`, beside `test-runs.tsv`; `codex-review` writes one too when it stops a codex that ran past `codex_minutes`.
- `make test` and `scripts/test.sh` refuse to run under codex, where `CODEX_SANDBOX` or
  `CODEX_THREAD_ID` is set.
- Each `make test` run adds a start line and an end line to the main checkout's `.swarm/test-runs.tsv`: its times, `JOBS`, filter, branch, load, CPUs, the other runs going (load, CPUs and runs read again at the end) and its exit status. A run killed with KILL writes no end line, so the next run writes one for it: status 137, with `-` for the end time, seconds, load, CPUs and other runs, which nobody measured. `swarm.sh flow` leaves it out, as it does every run with a status of 128 or more. `flow` reads the file in its `test_runs` section: the full runs by how many ran at once, and the median and p90 seconds of builders' runs on `story/*` branches. The section's `timeouts` column counts the test files that ran past `TEST_FILE_TIMEOUT` in the window, from `make test`'s `reap` lines (not `codex-review`'s).
- Each `swarm.sh status` and `next` run adds a row to `.swarm/run-times.tsv`: when it started, the command, the seconds it took and the load average. `swarm.sh flow` reads it in its `run_times` section: per command, the runs, the median and p90 seconds, and the share that took over a minute, then a by-load block with each command's runs and median seconds per load band (under 10, 10-20, 20 and over, or `-` with no load).
- `make test` runs each test file from its own `TMPDIR` with `SWARM_PROJECT` naming a stand-in project, and fails a file whose `swarm.sh` reaches it: one that does not source `tests/test_helpers.sh` first, and run on its own from a pane would reach the lead's real project. `swarm.sh` also refuses to act on the checkout the tests run from, or a worktree of it, while `SWARM_FORBID_PROJECT` names it, which the runner and the prelude set.
- To cap how many `make test` runs go at once on your machine, across all projects, write a whole number to `~/.swarm/test-cap`. There is no cap by default: no file, an empty file and 0 all mean none. Each run holds a slot in `~/.swarm/test-slots/` while it goes. A run past the cap prints that it is waiting, with the PID and slot of each run ahead of it, and starts when one of them ends. The wait has no time limit: a run that is stopped (Ctrl-Z) or hung keeps its slot. To free a slot by hand, `rm -r` the slot path the message names. A `make test` that a test starts inside another run takes no slot.
- `scripts/select-tests.sh` prints the test files that cover this branch's changes against `origin/main`,
  using `scripts/test-map.tsv`. When a changed file has no row in the map, or its row finds no test, it
  prints every test file. A change under `bin/` selects by function: the tests that name a changed
  function, one of its callers up to `bin/swarm.sh`'s dispatch arms, or the command of an arm on that
  path, plus the tests that name the changed file or read all of `bin/`'s code as text. When it cannot follow the calls (a change
  outside any function, a call by a name built at run time, or a test that runs `swarm.sh` with no
  command in its text), it prints every test file. `--run` runs the list through `make test`, four files at a time,
  and never runs every test file. When a changed file would put every test file on the list, `--run` prints a line
  naming that file and saying CI's full run covers it. It still runs the tests that file's own row lists, and the
  tests for the other changed files. When none of them has a test, it runs nothing and exits 0. `--known` prints the list `--run` runs. To run every test file locally, run `make test`.
  `--functions` prints, instead, the functions the branch changed in `bin/swarm.sh` and `bin/lib/*.sh`:
  `<file>:<function>`, or `bin/swarm.sh:arm <command>` for a dispatch arm. For a changed `bin/lib/*.py`
  it prints the functions that run it. It prints `full` when a changed line in those files is outside
  any function, when no function runs the `.py`, or when a hook, script or test runs it. It prints
  nothing when the branch changes none of those files, or only blank lines outside their functions.
- On Bedrock, Vertex or Foundry, agents take the provider and model settings from your session;
  see [reference-building.md § Building](reference-building.md#building).

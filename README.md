# swarm-dev

[![CI](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml/badge.svg)](https://github.com/redscaresu/swarm-dev/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/redscaresu/swarm-dev/badge)](https://scorecard.dev/viewer/?uri=github.com/redscaresu/swarm-dev)

swarm-dev is a Claude Code plugin that runs a team of agents to build software while you watch.
You agree a piece of work with one agent. Others split it into stories of one pull request each,
try to break that plan, then build the stories in parallel, each in its own terminal pane and git
worktree. Every PR is reviewed before it merges, and the run stops whenever a decision is yours.

## Quick start

1. Install, then restart Claude Code: `claude plugin marketplace add redscaresu/swarm-dev && claude plugin install swarm-dev@swarm-dev`
2. In your project's git root, inside [herdr](https://herdr.dev), start `claude`.
3. Run `/swarm-dev:swarm`. After your yes it runs `swarm.sh init`.
4. Run `/swarm-dev:hld <title>` (`/hld` for short) and agree the design: a release's worth of work
   starts there. Then `/swarm-dev:swarm` plans and builds it, and stops each time it needs you.

[Getting started](#getting-started) has the details and what to check first.

![swarm.sh dash --watch on a demo project: what needs you and the epics on the left, recent work on the right](docs/assets/dash.gif)

## How it works

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/swarm-flow-dark.png">
  <img alt="How the swarm turns a design into merged PRs: swarm.sh init, /swarm-dev:hld, /swarm-dev:swarm, /plan-hld, /swarm-dev:epic, /plan-epic, your approval, the board, conductor, builders, review agent, merge" src="docs/assets/swarm-flow-light.png">
</picture>

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
   worktree and opens a PR. Once CI is green, a review agent and codex review it, and the builder
   fixes what they find. A story that fails twice is rebuilt once on Fable, the most capable model,
   then handed to the lead.
4. **Merge.** By default you merge each green, reviewed PR yourself. The lead merges one only when
   the agreed HLD over its work lists `merge` in its `grants:`.
   With `merge = agent`, the conductor merges it, except a story marked `costs: money`, which always
   waits for you. After a merge, main is judged by the checks it requires, and any other red check
   prints a `warning:` line. A required check that fails in GitHub Actions is rerun once; if it
   passes then, merge prints a `flaky:` line. If main is still red, the swarm writes a story to fix
   it and builds that first.

Your own Claude session is the lead. It runs `/swarm-dev:swarm`, watches the agents, and does the
stories no agent may: real cloud, credentials and anything hard to undo. Your steps in those are
marked **You:**. The board is plain Markdown in your repo, so a run can stop anywhere and the next
`/swarm-dev:swarm` picks up where it left off.

## Requirements

| Needs | Version | What for |
|---|---|---|
| [Claude Code](https://claude.com/claude-code) | 2.1.145+ | runs every agent |
| [herdr](https://herdr.dev) | 0.9.2+ | the terminal multiplexer: one pane per agent |
| [GitHub CLI](https://cli.github.com) | logged in | PRs, CI checks, merges |
| [codex CLI](https://github.com/openai/codex) | logged in | the second reviewer, a different model family |
| `git`, `python3`, `bash` | any recent | the `swarm.sh` scripts |
| a GitHub repo | with `make check` | CI and the pre-commit hook run it |
| [Obsidian](https://obsidian.md) | optional | browse the board: open the board folder as a vault, and `Board.base` shows stories by status and epic, and HLDs by status |

## Getting started

1. Install the plugin (above), then restart Claude Code.
2. In your project's root, run `claude` once and accept "do you trust this folder?". Agents can't
   start in an untrusted folder.
3. Inside herdr, run `claude`, then `/swarm-dev:swarm`. Type the whole name, since a shorter one can run
   a different command. After your yes, it runs `swarm.sh init`, which adds the board
   (`docs/epics/` and `docs/stories/`), `.claude/swarm/config`, and a CI workflow and pre-commit
   hook that run `make check`. It then stops and tells you to run `claude` in the project once and
   accept the trust prompt (step 2, if you have not).
4. Run `/swarm-dev:swarm` again. The first time, it asks once for your rules for builders: commit trailers,
   where credentials live, and commands that must never run. Commit the `.claude/swarm/brief.md`
   it writes.
5. Run `/swarm-dev:hld <title>`, agree the design, then run `/swarm-dev:swarm`: it plans the
   design into epics, asks you to agree each, and builds them. For one epic with no design, run
   `/swarm-dev:epic <title>` instead. Run `/swarm-dev:swarm` each time it stops for you.

Your agent can also answer "how do I use swarm-dev?" and "why did /swarm-dev:swarm stop?".

## When `/swarm-dev:swarm` stops for you

| You see | Do |
|---|---|
| a draft HLD | finish it with the co-author, then agree it; its `grants:` are yours to set |
| proposed epics | agree each with `/swarm-dev:epic`, or say what to change |
| a draft epic | finish it with the co-author, then agree it |
| proposed stories | approve them, or say what to change |
| a `lead` story | say go, and do its **You:** steps |
| a PR waiting for you | merge it, ask the lead to, or close it to send the story back; one under an HLD that grants `merge` the lead lands itself |
| a `blocked` or `later` item | nothing, or set it `ready` / `active` to start it |
| an agent's login expired | run `/login`, then tell `/swarm-dev:swarm` it's done |
| an agent stuck | read its pane (`herdr agent read <agent>`), then type into it or close it (`swarm.sh close <agent>` keeps its open PR and puts the story in review with it; add `--drop` to close the PR and build the story again) |

## Watching it

| Command | What it shows |
|---|---|
| `swarm.sh dash --watch` | The live dashboard above: what needs you, what is running, and merges per day ([details](docs/dash.md)). |
| `swarm.sh status` | Agents that need a look, what waits on you, and what runs next. |
| `swarm.sh flow` | Cost, CI health and the flaky tests, where stories spent their time (including how long a ready story waited for its build, and how long ready work sat with no build while its conductor ran), how each model did, how well the planner guessed which stories were easy and how big, what each review round found, which agents spend GitHub's API budget, and how long local `make test` runs take by how many ran at once. Finished GitHub history is cached in `.swarm/gh-cache/`, so a second run asks GitHub only for what is open or new (`--no-cache` reads it all again). |

The other commands are ones the lead runs; [reference.md § Commands](docs/reference.md#commands)
lists them all.

## Cost and safety

Every agent is a full Claude Code session on your own logins, so a run spends real tokens. On one
project a story's build averaged $5.75, or about $9 per merged PR with planning and review
included, at list prices. `swarm.sh flow` shows where your own tokens went.

- No agent touches real cloud or credentials. That work is a `lead` story, done in your session
  while you watch.
- Agents start with a short list of environment variables. A token you exported reaches a builder
  only when its story names it under `env:`.
- In a swarm project, a plugin hook guards every Claude session. It refuses raw PR merges (merges
  go through `swarm.sh merge`), a `git checkout` that would drop changes, and an agent's `pkill`.
- Nothing merges until you say so, unless you set `merge = agent`, or the agreed HLD over the work
  lists `merge` in its `grants:`, which only you set. `swarm.sh grants <PR URL>` shows the HLD and
  its grants. `swarm.sh merge` reads the grant at the head it merges, and refuses if a push has moved
  the head. Under `merge = human`, the lead merges a release only when every story merged since
  the last tag is under an agreed HLD that lists `release`.
- Under either merge mode, `swarm.sh merge --board` refuses the same board PRs as
  `swarm.sh board-pr open` ([reference.md § Merging](docs/reference.md#merging)).

Settings live in `.claude/swarm/config`; [reference.md § Settings](docs/reference.md#settings)
lists them all.

## Updating

When the lead merges a swarm-dev release with `swarm.sh merge --release`, it updates the plugin and
starts `swarm.sh upgrade` for the running agents itself. Then it asks you to restart the lead
session (`/exit`, then `claude --continue`). If a PR landed on the base after the release was
checked, it names the commits that shipped unchecked and updates nothing. In that case, or when
you release some other way, update by hand:

```bash
claude plugin marketplace update swarm-dev && claude plugin update swarm-dev@swarm-dev
```

Restart Claude Code afterwards. Agents already running stay on the old version until
`swarm.sh upgrade <epic>` restarts them on the new one, each resuming its own session. upgrade runs
detached until every agent is moved, and prints its log, `.swarm/upgrade-<version>.log`.

Upgrading to 0.27: an HLD that was split into epics before 0.27 has no `planned:` line. Once its
epics leave the board, `next` offers to plan it again. Add `planned: <date>` to its front matter
by hand.

## More

- [The method](docs/method.md): how planning, building and merging work, in short.
- [Reference](docs/reference.md): every rule, setting, command and log.
- [AGENTS.md](AGENTS.md) for working on swarm-dev itself, and [SECURITY.md](SECURITY.md) for
  reporting a vulnerability.
- `make test` stops a test file that runs past `TEST_FILE_TIMEOUT` seconds (600 unless set, three times that for the files in `SLOW`) and fails it as
  `TIMEOUT <file> after <n>s`, with the file's last 20 lines of output. It also adds a `reap` line naming the file to `.swarm/events.tsv`, beside `test-runs.tsv`; `codex-review` writes one too when it stops a codex that ran past `codex_minutes`.
- Each `make test` run adds a start line and an end line to the main checkout's `.swarm/test-runs.tsv`: its times, `JOBS`, filter, branch, load, CPUs, the other runs going (load, CPUs and runs read again at the end) and its exit status. `swarm.sh flow` reads it in its `test_runs` section: the full runs by how many ran at once, and the median and p90 seconds of builders' runs on `story/*` branches.
- To cap how many `make test` runs go at once on your machine, across all projects, write a whole number to `~/.swarm/test-cap`. There is no cap by default: no file, an empty file and 0 all mean none. A run past the cap prints that it is waiting and the PIDs of the runs that hold the slots, then starts when one of them ends. Each run holds a slot in `~/.swarm/test-slots/` while it goes. A `make test` that a test starts inside another run takes no slot.
- On Bedrock, Vertex or Foundry, agents take the provider and model settings from your session;
  see [reference.md § Building](docs/reference.md#building).

## License

Apache-2.0.

---
status: active
depends_on: [leaner-faster-swarm]
---

# Merges that need no hand cleanup, agents that cannot leak secrets, and builds that wait less

swarm-dev is now the user's main way of building software (2026-10-17), and the user approved this epic that day. It comes from what the lead saw on 2026-10-16 across infrafactory and swarm-dev:
- Conductors' uncommitted status edits in the main checkout broke the post-merge pull (infrafactory #597). The hand stash-and-pull routine deleted a live story earlier the same day.
- Each one-off took four extra steps and a CI run to leave the board (`finish`, then a board PR).
- A builder's test printed a fine-grained PAT into a transcript, which cost a key rotation. Panes inherit the user's whole shell environment.
- The lead merged through a one-line script to get past a hook, and a conductor chained a stray `swarm.sh merge` onto an unrelated command (PR 214).
- Codex was rate-limited for most of the day, so reviews fell back to the lead reading diffs.

The throughput numbers come from `swarm.sh outcomes` and git:
- `bin/swarm.sh` is 6778 lines, and 29 of the day's merges touched it.
- 55% of story PRs needed main merged in (leaner-faster-swarm's baseline).
- The three largest stories each cost $12–15 and took 5.5–7 hours from start to merge.
- swarm-dev CI takes about 10 minutes, and every review round waits on it.

**Done when:**
- **Board state out of git.** A story's `status`, `attempts`, `prs` and other front-matter fields that swarm.sh writes live in `.swarm/state/`, not in tracked files. Tracked story files change only through PRs. `reconcile` loses its backup-and-restore step. A test shows that a conductor marking a story `review` leaves `git status` clean, and that a PR deleting that story pulls cleanly.
- **A story's PR removes its story.** When the board is inside the repo being built, a builder's PR deletes its own story file (the epic's last story deletes the epic file too), so the board updates when the code merges. A story on an external board (another repo or a notes vault, which the builder leaves alone today, bin/swarm.sh:2330-2333) and a story that ends with no PR still leave through `finish` after the merge. A test covers a one-off, an epic story and an external-board story.
- **Agents get an allowlist, not the user's environment.** Panes start with a fixed set of environment variables (`PATH`, `HOME`, `TERM`, locale, and the ones swarm.sh sets). Any other variable reaches a pane only when the story names it under `env:`. A test starts a pane with a fake secret in the parent environment and shows the builder cannot see it unless the story names it.
- **One merge path.** `swarm.sh merge` is the only merge command any role runs. It checks the head SHA and green checks, and holds `costs: money` stories. The merge guard hook blocks every other form, and the lead's docs stop telling it to write merge scripts. A test shows the hook blocks a raw `gh pr merge` and a `swarm.sh merge` chained into another command.
- **A fallback reviewer.** When codex answers with a usage limit, the review step starts a review agent on another model family or tier (set in config), logs it as `reviewer: fallback`, and the PR body says so. A test stubs codex's limit message and shows the fallback runs.
- **swarm.sh split by command.** `bin/swarm.sh` keeps dispatch and shared helpers, and each command group lives in `bin/lib/<group>.sh`. No file is over 1500 lines. The split moves code without changing it (the test suite passes unchanged), so the story size cap below does not apply to it; it may land as up to three PRs, one per group of commands. It merges first, alone, before any other story of the epic starts. After the epic, `flow` reports the share of PRs that needed main merged in, set beside the 55% baseline.
- **Story size cap.** plan-epic's decompose and skeptic briefs cap a story at one new command or one changed behaviour, and an estimated diff of about 300 lines. A skeptic refutes any story over the cap. The plan report lists each story's estimate.
- **CI under 4 minutes.** The test files run in parallel (CI and `make test`), and the CI run on this epic's last PR takes under 4 minutes.
- **Cost beside timings.** `outcomes` and `flow` print each story's cost next to its start-to-PR and PR-to-merge minutes, and `flow` sums cost per epic.
- **Telemetry for where the time goes and what breaks.** Each item reads from events.tsv, findings.tsv and `gh`, adds no new store, and has a test on fixture data. Each one gets a row in docs/features.tsv, so `features` flags any that nobody reads.
  - **Time in state:** `outcomes` splits each story's start-to-merge minutes into building, CI running, waiting for review, fixing findings, and waiting for a merge (the lead's or the user's). `flow` sums them per epic, so the largest wait shows first.
  - **CI health:** per project, the median CI minutes per PR head, the red runs per PR, and flakes (a red run followed by a green one on the same head SHA).
  - **Incidents:** swarm.sh logs an `incident` event for a reconcile pull that fails, a `wait` that times out, an agent stopped on a login, a merge that the guard hook blocks, a codex usage limit, and a builder that went idle with no PR. `flow` counts them per day by kind.
  - **Lead queue wait:** for each held, escalated or awaiting-merge item, the minutes between entering the lead's queue and leaving it, as a median and maximum per day.
  - **Rework:** a merged PR that a later PR fixes within 7 days (the later PR names it, or `log-finding --reviewer escaped` points at it) counts against the first PR's story, model and reviewer in `review-yield`.
- **`dash --project` runs from any directory.** Today it fails with "not in a swarm project" unless the shell is inside a project (the user hit it on 2026-10-17). When every frame is named with `--project`, dash needs no project around the current directory. A test runs it from a temp dir.
- **init sets up a new project like infrafactory.** `swarm.sh init` writes a CI board-only fast path, a pre-commit hook that runs the project's `check`, and an optional `commit_trailers` config line that builders add to every commit. A test runs init on an empty repo and checks each one.

**Out of scope:** remote or cloud-hosted agents, and a web UI beyond `dash`.

**Constraints:**
- The split story merges before any other story of this epic, because every other story touches swarm.sh.
- New settings ship off where they change behaviour (the env allowlist ships on, because it is a safety fix). A switch-on is its own lead story.
- Planned with the plan-epic and conductor that leaner-faster-swarm releases. The lead installs that release (`claude plugin update`) before planning.

**Your part:** none. The lead plans, builds and merges, since swarm-dev is merge = agent.

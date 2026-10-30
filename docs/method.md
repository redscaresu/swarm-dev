# The method

Work is planned top-down, you approve each level before the next is made, and every agent at every
level runs in its own herdr pane so you can watch it. This is the short guide. The detail behind
each step is in the reference files that [`reference.md`](reference.md) lists.

## The planning chain

1. **HLD** (optional): `/hld <title>` opens a pane where you write `docs/hld/YYYY-MM-DD-<slug>.md`
   with a co-author: a release's worth of work, and the `grants:` (`epics`, `stories`, `merge`,
   `release`) that say what the lead may do under it unasked. `/plan-hld` then splits the agreed
   HLD into epics (reference-planning.md § Writing an HLD, § Decomposing an HLD).
2. **Epic**: `/epic <title>` opens a pane on the most capable model, where you write
   `docs/epics/<slug>.md` with it as `status: draft`: the problem with evidence, goals that can be
   checked, non-goals and constraints. A reviewer attacks the draft, and it becomes `active` only
   when you agree it (reference-planning.md § Writing an epic).
3. **Stories**: `/plan-epic <epic>` splits the agreed epic into one-PR stories. A critic and codex
   check them for gaps and overlaps, a skeptic each `risk: high` one (reference-planning.md § Scoping an epic).
4. **Build**: `swarm.sh conduct <epic>` hands the epic to a fresh conductor, which builds its
   `ready` stories in parallel panes and starts a review agent on each PR as it opens. The review
   agent merges the PR, or hands it to you to merge (reference-building.md § Building, reference-merging.md § Merging). With a
   merge queue each reviewed PR is enqueued at once, else they merge one at a time. A PR whose base gained code since its CI ran gets the base merged in on GitHub
   (by its builder on a conflict) and runs CI again before it merges. Two stories clash only when their `touches` name the same file in the same repo and the same first word of a part (`file:part`), or when both name the bare file. A bare
   file does not clash with a part of it. A part's first word skips a leading `§`, `#`, "the", "a" or "an". Otherwise both build at once. A builder whose PR conflicts with its base merges its base in, resolves it, reruns
   the tests and pushes; a conflict never sends a story back to `ready`. Codex reviews every round
   (one review whose findings went back to the builder), `/code-review` only round 1, when it changes
   code. A review on the latest head whose findings are all declined is a pass: the review agent
   rebuts each in the PR and logs it as declined (reference-logs.md § The outer loop). It then marks the story in review on the head it reviewed
   and merges the PR under `merge = agent` or a `merge` grant, or hands it to you. An epic is done when its last story's PR deletes the epic file. The conductor starts the builds and review agents and never reviews or merges a PR. It ends the epic with its report, the lead's only sign it has finished, written only once no agent work is left: no story of the epic is ready, building, blocked on an agent's work, or in review with its review agent still to act on it. A merge or handover note says so with a `finish:` line; the conductor then closes its idle review agents and reports. A story blocked on a `lead` story waits on you and holds nothing up: the report lists it for you.

`/swarm-dev:swarm` runs the chain once an HLD or epic is agreed. `swarm.sh next` reads the board and names the next
step (when it says to wait, it also starts a conductor for any ready work that has none), `/swarm-dev:swarm` does it and loops, and it stops only at an approval, a draft HLD or epic, a plan or finish PR
awaiting merge, a `lead` story, or a `later` epic. On an empty board it explains the flow instead. After the step,
`next` prints `idle:` lines for capacity nothing uses: a blocked story an agent builds whose
`depends_on` story (one an agent builds, not in review) shares no part in `touches` with it and is not named in its `needs:` line
(the lead drops the dependency or names it in the story's `needs:` line), and a ready story with no build, ready for `queue_minutes`, whose `touches` share no part with a running build
(the lead sends its conductor a note, or starts it with `swarm.sh story --strict`). It also names a draft or later epic of the current stage with nothing left to wait on, and an active epic with no stories that was never built and has no plan running, each unless its own step already names it (the first is the user's to start, or planned unasked when it is a later epic with no stories; the lead plans the second with `/swarm-dev:plan-epic`). When the step leaves the builders idle and no
story is buildable, it also prints the project with up to five candidates for a one-off: the findings declined as `out-of-scope` or `deferred` in the last 30 days that no story has filed yet (the lead records each one
it files as filed in the findings log). With nothing to offer it prints no project line. Those declined findings
are the swarm's own list of follow-ups. The board is the
only state, so a run can stop anywhere and the next `/swarm-dev:swarm` continues. Building comes
first (a conductor still working, then an already-started one-off with `resume <slug>`, then an active epic's ready stories with `conduct <epic>`, then new one-offs), then reporting (`conduct <epic>` for a built epic: all its stories have merged and left the board, and its report is missing or older than the last merge), then
planning (an active epic with no stories that was never built). An epic is planned
only once every epic it `depends_on` is done or has only stories in `review` left, so its stories
are scoped against code that exists. That can happen while a conductor is still working: `next`
then names the planning first, and the lead keeps waiting on the conductor in the background.
When `next` says to wait on a conductor, it also lists each ready `lead` story that a blocked story
depends on (`also: lead <slug> blocks <slugs>`). It also lists a story that is blocked with no `depends_on`, if its kind is one no agent builds: only the lead can ready it. A blocked story of a kind an agent builds gets no `also:` line. The lead runs the listed stories while it waits, since no conductor will build them. `status` reads a blocked story's line as `blocked: <slug> (by <parents>, which no agent builds)` when every open parent is work no agent builds. That is a story of a kind no agent builds (in any status), a story blocked with no `depends_on`, or a hand step like `operator:<x>`.

## Who does what

Three parties do the work, and the plan decides which one does each step, not the build.

- **You** agree each HLD and epic, approve the stories, merge PRs (with `merge = human`), say go
  before each `lead` story, and do its **You:** steps. An agreed HLD's `grants:`, which only you set,
  hand the lead some of that: `epics` and `stories` skip your agreement of its epics and approval of
  their stories; `merge` lets it merge a story or board PR under the HLD, and `release` a release whose
  stories are all under HLDs that grant it, with `swarm.sh merge`. A `costs: money` PR still waits for you.
- **The lead** is your Claude Code session, the one you run `/swarm-dev:swarm` in. It supervises,
  reviews and runs `lead` stories, never the agents' work. Its messages to agents go through
  `swarm.sh tell`, never a bare `herdr agent prompt`, and when the board is in the project's repo its
  board edits go through `swarm.sh board-pr`, each in its own worktree, never the main checkout
  (reference-lead.md § The lead). Only a plan or agreement board PR gets a codex review; an edit, a hold or a finish lands on green CI. If it stops while `next` names a step it has not started, a hook sends it back once.
- **Agents** plan, conduct and build everything else, each in its own pane, builders in a worktree too.

A story is `kind: lead`, never an agent's, when it:

- changes real cloud, uses credentials, or changes permissions;
- is hard to undo (deletes data, turns something off, a production change): its **Done when** names
  your go-ahead;
- needs a person: a decision, a portal click, another team's approval, a network only you can reach,
  or the answer to an open question, which the board's **Waiting on you** view then lists. That step
  is a **You:** line in the story, and the lead does the rest around it.

A merge is never a story. A `kind` other than code, docs, chore or lead is never built: `swarm.sh` stops and names it.

**Planned up front.** `/epic` writes each epic's **Your part**, the human steps it expects, and
`/plan-epic` turns them into `lead` stories and ends its report with **What you will do**, so you see
your share of the work before you approve it. A step found during the build that needs you is a new
`lead` story, not done quietly.

**Every stop names its exit.** A `lead` story says what it needs from you in its body, and each **You:**
step says how the lead learns it is done. A status or flag raised for you says who clears it and how. `wait --lead` carries idle capacity too: `next`'s `idle:` lines for blocked stories and for ready stories with no build wake the lead while a conductor works, and `status` and `dash` show them. Stuck agents wake the lead the same way: an agent on a prompt, a dialog, an expired login, an API error no `wait` is resuming, or manual mode gives a `prompt:` line that names who clears it. So do stuck PRs: a story PR reviewed, green and left unmerged past `queue_minutes` gives an `unmerged:` line, and one that conflicts with its base a `conflict:` line, each with its exit. From v0.30.0 four more lines join them: `stuck:` for a builder idle on findings or a conflict, `main-red:` for a red base, `reported:` for a conductor that reported with agent work left, and `sign-blocked:` for builders that cannot sign their work.

## The board

The board is files: `docs/epics/` and `docs/stories/`, one file per item, with front
matter the scripts read. There is no shared board file to conflict on; the PR that finishes a
story deletes its file, and the PR is the record. A project can move the board (§ Configuring a
project). `templates/docs/` holds the READMEs that define each format and an Obsidian Base
(`Board.base`) that shows the board as a view.

## Configuring a project

`swarm.sh init`, run from the project's git root, copies the board templates into `board_dir` without
overwriting a file (except a `Board.base` that is a past template nobody edited, which gets the current one),
creates `.claude/swarm/` with a commented `commit_trailers` line, and adds `.swarm/` and the board's Obsidian
lines to `.gitignore`. It also sets up checks. With no `.github/workflows`, it writes a `ci.yml` that runs
`make check` on each PR and on pushes to origin's default branch. It reads that branch from the cached
`origin/HEAD`, and asks origin only when that is missing, without prompting and for at most 15 seconds; with
no answer it writes no CI and says so. The step fails, naming the target, when make has no `check` target.
Its gate, `.github/swarm-board-only.sh`, skips the checks for a PR or push that changes only the board's own
files (`stories/`, `epics/`, `hld/`, `Board.base` and `.obsidian/` under `board_dir`, so other pages in
`docs/` still get checked). A board outside the repo gets the workflow without the gate. A `ci.yml` that init
wrote carries a marker line; init leaves it alone after that and only writes the gate again if it is missing.
With other workflows already there, init leaves them, writes the gate, and prints the step to add to the job
that runs your checks. It also writes a git pre-commit hook that runs `make check`, skipping a commit that
changes only the board's own files. While make has no `check` target, the hook only warns; CI is the check
that fails. When a hook exists, or the repo sets `core.hooksPath`, init writes no hook and prints the lines
to add before any `exec` in it (for husky, to `.husky/pre-commit`). A global `core.hooksPath` gets no hook
and no lines, since a hook there runs in every repo. Last, init lists the files it wrote that git does not
track yet, for you to commit: CI runs only once its workflow is committed. The next `/swarm-dev:swarm` asks
once for the brief (`.claude/swarm/brief.md`) and writes only what you say; an empty file means you declined.

`.claude/swarm/config` holds `key = value` lines and `#` comments, parsed and never run; an unknown
key or a bad value stops `swarm.sh` with the file and line. `swarm.sh config` prints each setting and its source.

| Key | Default | What it does |
|---|---|---|
| `board_dir` | `docs` | where the board is, relative to the project unless absolute; a `"` or `\` in it is refused, since init writes it into quoted strings |
| `repos_dir` | the project's parent | where a story's `repo: <name>` is found |
| `base_branches` | origin's default branch | branches to try, in order, as the base: `dev main` means `dev` where origin has it, else `main`. A repo that has none of them stops the command |
| `sign_commits` | `false` | `true`: every builder's and conductor's brief tells it to sign each commit and merge with `-S`, and to stop if it cannot; `swarm.sh board-pr`'s commit and a stacked start's merge pass `-S` too |
| `merge` | `human` | `human`: a green, reviewed PR waits for you. The lead merges one only when the agreed HLD over it grants `merge`, and never a `costs: money` one; under that grant a story's review agent may also merge that story's PR. `agent`: each story's review agent merges that story's PR, except a story with `costs: money` or a story PR that changes `.claude/`, `.github/`, `hooks/` or a root makefile, which `swarm.sh merge` holds for you (reference-merging.md § Merging); the conductor merges no story PR |
| `stall_minutes` | `30` | a working builder with no sign of life this long is `stalled?`, and `dash` and `wait --stall` flag it; `wait` also returns `stuck` on a busy agent whose pane has not changed this long while it runs no background task. To `wait` and `dash`, a test suite running in the agent's pane (`make test`, `make check`, `scripts/test.sh`) or a background task its session waits on is work for up to 3 times this long, so the agent is not stalled. `wait --stall` also does not call a builder stalled while git cannot sign its uncommitted work (gpg-agent or ssh-agent holds no unlocked key), for up to 3 times this long after its own last sign of life. A test suite in that time also keeps it from being stuck (reference-building.md § Building) |
| `queue_minutes` | `30` | a story PR green and mergeable this long with no review agent on its head is `queued:` in `watch` and `next` (reference-building.md § Building); one reviewed and left unmerged this long is `unmerged:` in `wait --lead` |
| `sonnet_share` | `0` | `N`: one in N `kind: code` stories marked `easy: true` and without `risk: high` is built on Sonnet, to compare it with Opus. `0` is off (reference-models.md § Model and effort) |
| `escalate_after` | `2` | `N`: a story whose `attempts:` has reached N is built on Fable. `0` is off (reference-models.md § Model and effort) |
| `escalate_ladder` | empty | models from low to high, each once, such as `sonnet,opus,fable`: swarm.sh steps a struggling build up to the next one in the same worktree. Empty is off (reference-models.md § The escalation ladder) |
| `step_up_findings` | `3` | `N`: with `escalate_ladder` set, a build's Nth round of review findings steps it up instead of being sent (reference-models.md § Settings) |
| `top_rung_rounds` | `2` | `N`: with `escalate_ladder` set, the Nth round of review findings on its top rung holds the story for the lead instead; at least `2` (reference-models.md § Settings) |
| `builder_subagent_model` | empty | a model such as `haiku` that builders' subagents run on. Empty leaves Claude Code's choice (reference-models.md § Settings) |
| `goal` | `off` | `N`: each builder gets a `/goal` condition and N more turns to meet it. Needs Claude Code 2.1.269 or later (reference-building.md § Building) |
| `codex_minutes` | `10` | `swarm.sh codex-review` stops codex after this many minutes (reference-building.md § Building) |
| `fallback_reviewer` | empty | a model such as `sonnet` that reviews in codex's place when codex hits its usage limit. Empty skips the review (reference-building.md § Building) |
| `lead` | `off` | `session`: a lead session acts for you, so `dash` splits needs you in two: your steps, and the lead's queue (reference-models.md § Settings) |
| `merge_admin` | `off` | `on`: `swarm.sh merge` passes `--admin` to `gh pr merge`, for a repo whose ruleset requires an approving review, but only once its own checks pass and the base has no other rule `--admin` would skip (reference-models.md § Settings) |
| `lead_epics` | `off` | `on`: the lead may set an epic `active` on its own. `off`: an epic that is not `active` yet (new, draft, `later`, `split`, `review` or `done`) goes `active` only with your agreement (`agreed:`), a `parent:`, or an HLD that grants `epics` (`swarm.sh grants`; reference-models.md § Settings), and `swarm.sh board-pr` refuses a board PR that sets one `active` with none of them |
| `commit_trailers` | empty | trailers such as `Co-Authored-By: Name <email>`, `;` between several, that every builder's brief tells it to end each commit with (reference-models.md § Settings) |
| `agent_env` | empty | variable names, separated by spaces, that every agent of every role gets with your session's values, such as a provider's key and endpoint (reference-models.md § Settings) |

The project is `$SWARM_PROJECT` if set, else the nearest directory up with `.claude/swarm/config`,
else the git repo you are in; a worktree resolves to its main checkout. It need not be a git repo: a
board in a notes vault works if every story names its `repo:`. When the board is not in the story's
repo, the builder leaves the story file alone and the lead runs `swarm.sh finish <slug>` on merge.

## Where the rest is

[`reference.md`](reference.md) holds the commands and lists the files that hold the rest: the lead's
board PRs and wake, epics, model and effort, settings, scoping, building, logs, merging and releases.

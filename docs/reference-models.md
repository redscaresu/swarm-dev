# Reference: Models and settings

Part of [the reference](reference.md), which lists every section and the file that holds it.

## Model and effort

Every agent's model and effort come from its role, set in one place: `policy()` in
`bin/swarm.sh` (`swarm.sh policy <role>` prints it). Spend on judgment, save on reading:

- **Design is Fable.** An epic is co-written at `high`, because the user waits on every turn, and
  attacked at `xhigh` before it is agreed.
- **Judgment is Opus.** An epic's decomposition into stories runs at `xhigh`. Skeptics and the
  critic run at `high`; a `risk: high` story gets a skeptic, and the critic checks every story.
- **Reading is Sonnet, chores are Haiku.** Surveys read and cite at `high`, since they feed the
  lead, and docs run on Sonnet at `medium`. Chores run on Haiku at `medium`: their result is a
  mechanical diff, checked by the conductor.
- **Building code is Opus at `high`**, and at `xhigh` for a story marked `risk: high`. To find out
  whether Sonnet would do as well, `sonnet_share = N` builds one in N of the other code stories
  marked `easy: true` on Sonnet at `high` (`code-sonnet`); every other code story stays on Opus.
  The slug fixes the pick, a retry goes back to Opus, and each build's agents.tsv line says which
  model built it. It ships off (`0`).
- **Codex is the cross-model check**, read-only, because a different model family shares fewer
  blind spots with the one that wrote the plan.
- **Below the design level, Fable is escalation only**: a story that failed twice, or an epic whose
  contradictions no one can reconcile. A story whose `attempts:` has reached `escalate_after` (2 by
  default) is built as `escalate`, on Fable at `xhigh`, ahead of `risk: high` and `sonnet_share`.
  A `kind: lead` story never escalates, since no agent builds it. `swarm.sh close <slug>` counts a
  failed build of a code, docs or chore story. When the story is still `ready`, its builder is still
  open and no PR on `story/<slug>` has merged or is open with auto-merge set, it raises `attempts:`
  by one and clears the attempt away: it removes the worktree and `story/<slug>`, here and on
  origin. The next build then starts fresh, and the third runs on Fable.

  While a PR on `story/<slug>` is open, a bare close closes the builder alone and puts the story in
  review with that PR, as `swarm.sh review` does (held instead, as review holds it, while a parent
  is open). The PR, its branch and worktree stay, nothing is counted, and close prints `kept:`
  naming the PR. It reads the head's checks and review once, and prints `kept (not green)` (or
  `checks not read` when gh could not tell), `kept (not reviewed)` or both when they have not
  passed. The story's state gets a `kept: <date> close <cause> (<what has not passed>)` line, so
  nothing takes it for reviewed: `status` and `wait --lead` list it as `kept: <slug> <PR URL> (not
  reviewed)`, never as one to merge, `dash` draws it as `review kept story <slug>` with
  `swarm.sh review` and `swarm.sh close <slug> --drop` as its ways out, a conductor does not count
  it as in review for its epic's end, and `swarm.sh review <slug> <PR URL>` clears the line once it
  passes. It is logged as a `kept`
  event, never a `review`, so no report counts a give-up as a hand-off. The state is written before
  the builder closes, and goes back to `ready` when its pane cannot be closed. Reconcile then finishes the story when the PR merges, or sends it back to `ready`
  when it closes unmerged. `swarm.sh close <slug> [cause] --drop` clears the attempt even then,
  including after a bare close kept it (in review, or held) and its builder has gone, as long as the
  PR is open. It counts the attempt, sends a story in review back to `ready` once the count or hold
  is written (a step that fails first leaves it in review with its PR), closes each open PR unmerged with a
  comment naming the attempt, and prints each step that succeeded as `dropped:`, with the head SHA
  of each branch (read before it is deleted) and of each PR, so the work can be restored.

  Any other close after `review` or a merge, or after the builder has gone, counts nothing, and
  `reconcile` sending a story back to `ready` never counts. If gh cannot list the PRs, the close
  counts and clears nothing and says why on stderr; if its list cannot be read, nothing closes.
  `swarm.sh close <slug> <cause> [--drop]` also says why the builder stopped: `met`, `stalled` and
  `bound` count as above, while `impossible`, `paused` and `cleared-on-error` are not attempts and
  leave `attempts:` as it was. Those three hand the story to the lead and clear its build, so while
  its PR is open they are refused without `--drop`, before anything closes. `impossible` clears the
  build away whenever it hands the story on (below).
  `paused` and `cleared-on-error` clear it when the close ends a build under the same conditions; otherwise they clear nothing and print
  `not held:`. An unknown cause
  is refused before anything closes, and with `goal` on, so is a close with no cause while the story
  is `ready`. `impossible` means the builder replied `IMPOSSIBLE:`, so the **Done when** cannot be
  met: the story becomes `kind: lead` with `escalated_from:` and a block with the lead's choices
  (re-scope the **Done when**, then `swarm.sh reset <slug> <reason>`, or `swarm.sh drop <slug>
  <reason>`). Like a failed Fable build it is the lead's, with no **You:** step, so `next` prints
  `escalated <slug>` for it and it is never under waiting on you. `paused` and `cleared-on-error`
  hold the story the same way, with `held_for: <cause>`, whenever they clear its build. The lead lifts
  the hold with `swarm.sh reset <slug> <reason>`, which puts the kind back and keeps `attempts:`.
  That is not the story's one reset, and a later pause or error holds it again. `impossible` hands on
  any story still `ready` of a kind an agent builds, and clears its worktree and
  `story/<slug>` here and on origin so a reset builds it again. When the close lists the story's PRs,
  it closes each open one with `gh pr close`. When it lists none (its builder is gone, gh cannot list
  them), a bare close is refused before anything closes, because deleting `story/<slug>` on origin
  makes GitHub close any PR still open on that branch. With `--drop` it goes ahead, running no
  `gh pr close`, and the block says the PRs were not listed, so the lead looks before resetting.
  While a PR merged or is merging (auto-merge set), `impossible` is refused, `--drop` or not. Any
  other story, and a name with no story file, is refused before anything closes.
- **After Fable, the lead decides.** When the build a counted close ends was `escalate`, the close
  hands the story to the lead: `kind: lead`, `escalated_from:` its kind (`code (default)` when it
  had no `kind:` line), still `ready`, and a block with the attempts' PRs (from the same `gh pr
  list`) and the lead's two choices. The block is in `.swarm/escalated/<slug>`,
  not in the tracked story file. It has no **You:** step, because by the
  user's decision of 2026-10-15 the lead decides and then tells the user what it chose and why.
  `next` prints `escalated <slug>` for it, ahead of `gate`. The lead either re-scopes the story and
  runs `swarm.sh reset <slug> <reason>`, which removes `attempts:` and `escalated_from:` and deletes the block,
  or drops it. While the story still says `kind: lead`, reset puts its kind back (no `kind:` line
  for `code (default)`), so the file is its committed text again; a kind the lead set itself stays.
  A builder reads its story in its worktree, so when the board is in the story's repo the re-scope
  merges as a board PR first.
  Then the lead runs `reset` and pulls the board in one go: `reset` puts the file back to its
  committed text, so the pull brings in the re-scope, and `story` reads its kind, repo, epic and
  risk from that. `swarm.sh drop <slug> <reason>` takes a dropped story off the board as `finish`
  does, and it refuses any story that is not escalated. On a board in the repo, `finish` and `drop`
  never touch the main checkout: each deletes the file in the board PR `finish-<slug>` or
  `drop-<slug>` (titled `Drop <slug>: <reason>`) and prints the `swarm.sh merge --board <url>` that
  lands it; a second run pushes to the same PR. A file that is not on origin's base yet (an unmerged
  board PR adds it) is refused, and the worktree and branch the failed run started are removed. On a
  board outside the repo they delete the file where it is. A story is reset at most once: `reset`
  refuses a slug that events.tsv already shows reset, and names when, and a story that escalates
  again after its reset is offered only drop, in its block and in `next`. An
  escalated story is the lead's, so it is not listed under waiting on you (`status`, `dash`,
  `gate`). Each step is a line in events.tsv with its UTC time, for the training data:
  `escalate <slug>` when the build starts (`ok (attempt <n>)`), `dialog <slug>` when a conductor
  answers its usage-credits consent (`accepted` or `dismissed`), `escalated <slug>` at the close
  (`ok (attempts <n>, <k> PRs)`), and `reset` or `drop <slug>` with `ok (<reason>)`.
- **Measure before tuning.** `swarm.sh` records every agent it starts (role, model, effort,
  session) in `.swarm/agents.tsv`, and the `cost` section of `swarm.sh flow [--since YYYY-MM-DD]` turns that and Claude
  Code's logs into tokens and estimated cost per role, and per ladder rung for each step-up. The lead's own sessions count too, under
  `lead`: every session in the project's Claude Code directory that agents.tsv does not name. Change
  `policy()` from that table, not from a guess.
- **The conductor is Opus at `high`, one fresh session per epic**, on the standard context window,
  never 1M. A conductor re-reads its whole context every turn: on the project this came from, one
  long-lived lead session was 80% of all tokens over three days (3.6B of 4.5B, at up to 1M
  context). The board carries the state, so a new conductor costs little.
- **A review agent is Opus at `high`**, the model the conductor reviewed with before each PR got its
  own (role `review`, started by `swarm.sh review-agent`). One per PR, started when it opens, so
  reviews run side by side and the conductor's own context holds none of them.
- **The fallback reviewer runs on the model `fallback_reviewer` names, at `high`** (role
  `review-fallback`). codex-review starts it only when codex hits its usage limit and the key is set.

## Settings

The table in [the guide](method.md) lists every key. The rules the table leaves out:

- `merge` (default `human`): `human`: a green, reviewed PR waits for you. The lead merges one only when the agreed HLD over it grants `merge`, and never a `costs: money` one. Under that grant a story's review agent, `review-<slug>`, may also merge that story's PR (§ Merging). `agent`: each story's review agent merges that story's PR, except a PR `swarm.sh merge` holds for you (§ Merging); the conductor merges no story PR
- `stall_minutes` (default `30`): a story's builder that is working this long with no sign of life (no commit in its worktree, no edit there to a file `git status` lists, no update to its PR, no swarm action on its story) is `stalled?`: `wait --stall` returns on it. `dash` shows every working agent's time since its last sign of life after its state (`working 12m`); past this it shows `stalled 40m` instead, marks the agent `!` and lists it under needs you (with `lead = session`, under the lead's queue). An agent with no story (a conductor or planner) has its own `events.tsv` lines as signs: those naming it, and once it has a start line, those its pane ran, nudges, resumes, resends, incidents and failed tells excepted. Any agent with a Claude session, builder or not, also counts its session log (`.jsonl`). For `wait --stall` that is the newest entry of the agent's own work (an assistant message, a tool call or a tool result) in the log or in its Task subagents' logs (`<session>/subagents/*.jsonl`). Compaction, summary and background-task entries do not count, because a session hung on a command keeps writing them. `dash` still counts the log's last write. `wait` and `dash` also count a test suite running in the agent's pane as work: a process under the pane's shell that runs `make test`, `make check`, or `scripts/test.sh` (through a shell, or run directly). While that run is younger than 3 times `stall_minutes`, `wait --stall` finds no stall and `wait` does not say `stuck: no output`. `dash` shows the agent as `working <N>m`, with no `!` and no `look at` line. A command that only names one, such as `grep scripts/test.sh` or `cat test`, is not a test run, and neither is one in another pane. When herdr's process info or the process list cannot be read, the run is not seen, and the stall fires as it would without one. An older run may be hung, so it no longer counts: the builder can stall, and `wait` can say `stuck`, as if no run were there. The `longest-running:` line then names the leaf under the run if its tool shell started after the builder's last own work (see below). `dash` shows such an agent `stalled`, with its `look at` line. A background task the agent's session waits on counts as work for `wait --stall` and `dash` in the same way: a shell, an async subagent or a monitor it started, with no `<task-notification>` carrying a `<status>` for it since. It counts only while its launch is younger than 3 times `stall_minutes`, so a server left running in the background does not keep a builder from stalling. A codex builder has no session log, so it has no background task. For `wait --stall` alone, a builder whose signer cannot sign its uncommitted work (the signer probe says `blocked`) is not stalled either, while its last sign of life is under 3 times `stall_minutes` old (see `wait --stall` in [§ Building](reference-building.md#building)). `dash` reads an agent's processes and its background tasks only once it is past `stall_minutes`, so an agent working under it costs no read. When `wait --stall` finds a builder stalled, its `stalled:` line, and the `incident` line it logs in `events.tsv`, end `; longest-running: pid <PID>, <N> min: <program> (under <parents>)` when a foreground Bash call is running a command. That call is the newest of Claude Code's Bash tool shells, and it must have started after the builder's last own work: a shell started earlier (a `run_in_background` server, say) is not the foreground call, and the builder is hung somewhere else. From that shell the line follows the oldest child at each step down to the leaf, so a hung `sleep` under `make lint` names the `sleep`. Each process shows only its program name (ps's `comm`, so a path with spaces stays whole), never its arguments, which may hold a token. Processes outside a tool shell (caffeinate, an MCP or LSP server) are never named. When nothing is named, the line ends `; longest-running: none named (<why>)`: a codex builder, whose commands are not traced; no Bash tool call running a command; no tool shell started since its last own work; or a process list that could not be read. When the stall is stepped up (`escalate_ladder`), the `longest-running:` line follows `stepped up:` and says the step-up closed the pane, so the PID may be gone. The conductor checks the PID with `ps` and stops only a hung leaf with `kill <PID>`, then waits on the builder again; it closes the build as stalled when nothing is named or the builder stalls again. Working is its Claude session reporting busy, for `wait --stall` and `dash` alike, and herdr's working for a codex builder
- `queue_minutes` (default `30`): a story PR is queued when its head is green by `ci_gate`'s rule (every check run on every page and every commit status passed, at least one run), the last of them finished this many minutes ago, the PR is open and mergeable, its story is one an agent builds (never a `lead` story's), and that head has no review agent's review. A review counts when its findings file for the head is a pass (`## Findings`, no `head moved:`), or while the agent started on it (`.swarm/reviews/<slug>.head`) is still open in herdr with no file written: one that crashed, was closed or was tidied is no review. `watch` returns `queued: <repo> #<n> <branch> green <m>m with no review on <sha>` once per head, after it has reported the head's checks finished. `next`, while conductors work, prints the same line after its step's why for each such PR of every working conductor, ending in `(<conductor>)`, the one to send it to. A head is sent once: `watch` and `swarm.sh tell <conductor> note` (for each such line in the note) both record `queued <sha>` in `.swarm/state/watch-seen`, and neither `watch` nor `next` prints a recorded head again. `dash` and `status` do not look The same setting is how long a ready story waits with no build before `next` prints its `idle: <story> is ready with no build` line (see **`next`'s idle ready line** below). The same threshold sets when `wait --lead` prints `unmerged:` for a reviewed story PR left unmerged: its PR opened and its review written `queue_minutes` or more ago (§ The lead).
- `sonnet_share` (default `0`): `N`: one in N `kind: code` stories marked `easy: true` and without `risk: high` is built on Sonnet (role `code-sonnet`), so `swarm.sh outcomes` can compare it with Opus. The pick is the `cksum` of the slug mod N, so a slug always gets the same model. Only a story's first build is picked: a retry is built on Opus, or on Fable once `escalate_after` applies. `0` is off (§ Model and effort)
- `escalate_after` (default `2`): `N`: a story an agent builds whose `attempts:` has reached N is built on Fable (role `escalate`), whatever its kind, risk or `sonnet_share` pick. An absent `attempts:` is 0, and a value that is not a whole number is refused. `0` is off (§ Model and effort)
- `escalate_ladder` (default empty): models from low to high, separated by commas, such as `sonnet,opus,fable`. Each must be one of the models building roles run on (`haiku`, `sonnet`, `opus`, `fable`), named once and in that order (a skipped rung is fine, as in `opus,fable`), or the config is refused, so a step-up never steps down or comes back to a model. Empty is off, and `swarm.sh step-up` refuses (§ The escalation ladder). On or above the top rung, where no step-up is left (above it is a model past the ladder's top, such as an `escalate_after` Fable build with `sonnet,opus`), `swarm.sh tell <slug> findings` does not send a builder its `top_rung_rounds`-th findings round since it got there (or since the lead last reset the story), or any later one: the story is held for the lead (`kind: lead`, `held_for: top-rung`, for `reset` or `drop`) with those findings in its block, and the builder and its PR are kept
- `step_up_findings` (default `3`): `N`: with `escalate_ladder` set, `swarm.sh tell <slug> findings` steps a builder up instead of sending it its Nth findings round of the build, and the step-up trigger is `findings-N` (§ The escalation ladder). A value that is not a whole number of 1 or more is refused, naming the key
- `top_rung_rounds` (default `2`): `N`: with `escalate_ladder` set, a builder on or above the ladder's top rung is not sent its Nth findings round since it got there (or since the lead last reset the story), or any later one; the story is held for the lead instead (`escalate_ladder` above). A value that is not a whole number of 2 or more is refused, naming the key: at `1` every findings round after the lead lifts a hold would hold the story again
- `builder_subagent_model` (default empty): a model such as `haiku`: the agents that build a story start with `CLAUDE_CODE_SUBAGENT_MODEL` set to it and `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`, so their subagents (an Explore search, say) run on it. Planners and conductors are unchanged. Empty leaves Claude Code's choice
- `goal` (default `off`): `N`, such as `goal = 5`: `swarm.sh story` writes each builder a goal condition beside its brief, in `.swarm/briefs/<slug>.goal.md`. It refers to the story by the path its brief gives (relative to the worktree when the board is in the repo it builds): every item under **Done when** and **From review**, if any, holds. Then it adds the reply the brief asks for, a way out (reply `IMPOSSIBLE: <why>` and stop) and `or stop after N more turns`. Claude Code queues a long paste as a prompt instead of running it as `/goal`, so a `/goal` message over `GOAL_SEND_MAX` characters stops `story` before it makes a branch or worktree. Needs Claude Code 2.1.269 or later. Once the brief is taken up, `story` sends the builder the goal and fails if its session log does not show it set (§ Building, **The goal.**)
- `codex_minutes` (default `10`): `swarm.sh codex-review <base>`, which every brief and the lead use to run codex's review, stops codex after this many minutes: TERM to its whole process tree, a few seconds' grace, then KILL to whatever is left. It then prints `codex skipped: timed out after <N> min` and exits non-zero. Its events.tsv line says the same, and a `reap` line names the codex it stopped (see the audit log). It ships on (§ Scoping an epic)
- `fallback_reviewer` (default empty): a model such as `sonnet`. When codex reports a usage limit, `codex-review` starts a review agent on it in codex's place (role `review-fallback`), waits for its findings and prints them in codex's form. Empty keeps `codex skipped: usage limit`. § Building has the details
- `lead` (default `off`): `session`: a lead session acts for you, so `dash` splits needs you in two. Needs you keeps only your steps: a story with a **You:** step, an expired login, and each merge only you may make. A `costs: money` merge is always yours, and so is a `(protected path)` merge row, the PR `swarm.sh merge` holds for a protected path, and a `(dropped base lines)` row, the PR it holds because its merge of the base dropped base lines. With `merge = human`, so is any other `merge <PR>` row, unless the story's or epic's agreed HLD grants `merge`. So are a plan PR row, unless its HLD grants `merge`, and every finish PR row, grant or not. dash reads the grants from the board files. A `stage PR awaiting merge` row stays in the lead's queue. The other merge rows, an agent waiting on a prompt, a `lead` story with no **You:** step, every escalated story, a story a close kept (`review kept story <slug>`, with `swarm.sh review` and `swarm.sh close <slug> --drop`), a staged draft epic (`staged epic <slug>: stage v<T>, after v<P>`, with no `agree draft epic` row), a draft epic the lead may set active (`set draft epic <slug> active: <why>`, with no `agree draft epic` row either), a started story no agent works on (`no agent on story <slug>`, with the exit of `wait --lead`'s `no-agent:` line), an empty pane, an agent whose session is gone or unknown, and a stalled agent go in a `lead's queue` box under it, left out when empty. `next` and `status` are unchanged
- `merge_admin` (default `off`): `on`: `swarm.sh merge` passes `--admin` to `gh pr merge`, so it merges in a repo whose ruleset requires an approving review, which no agent can give. It does so only after the checks it always makes: the head is green, no `costs: money` hold applies, the `--board` or `--release` scope holds, and the head is the one `--head` names. `--admin` skips every rule on the base, not only the review, so `swarm.sh merge` first reads the base's rulesets and branch protection itself. It refuses while a status check they require is absent from the head, while they require the branch up to date (strict) and the head is behind the base, and whenever they hold a rule besides the review, the status checks and rules about pushes (deletion, force pushes, creation): a merge queue, required workflows, signatures, linear history, conversation resolution, deployments, code scanning or push restrictions. That includes the review rule's own thread resolution, and merge methods that leave out the one `swarm.sh merge` picks from the repo's settings. A classic protection field outside the few known to be safe is refused whatever its name, and a 404 from branch protection counts as unprotected only when GitHub says `Branch not protected`, since a token that cannot read protection gets a 404 too. The refusal names the rule. A red head, a held PR or a moved head is still refused before `gh pr merge` runs. Off, `swarm.sh merge` never passes `--admin` and reads none of these
- `review_verify` (default `ci`): what a story's review agent may run besides codex and `/code-review`. `ci`: every round reads the diff and trusts CI for the tests, with no local test run and no mutation run. `full`: round 1 may also run the project's tests for the files the PR changes (as its `AGENTS.md` or Makefile selects them, never the whole suite) and check the builder's mutation proofs: each FAIL line in the PR body names a test the diff adds or changes, and a proof it runs again breaks the fix only in a copy of the worktree. Rounds 2 and later run as `ci`, and so does a review agent started on round 2 or later. The brief and `review-agent --next` each print the line for their round. Any other value stops `swarm.sh` with the file and line
- `lead_epics` (default `off`): `on`: the lead may set an epic `active` on its own. `off`: an epic goes `active` only through the user or a grant. Any other value stops `swarm.sh` with the file and line
- `commit_trailers` (default empty): one or more trailers, `;` between them, such as `commit_trailers = Co-Authored-By: Ann <ann@example.com> ; Signed-off-by: Bo <bo@example.com>`. Each is a `Token: value` pair; anything else is refused. A `#` starts a comment, so no trailer can hold one. Every builder's brief tells it to end each commit message with them, one per line, and `swarm.sh board-pr` adds them to its commit, ahead of the trailers the brief names. `swarm.sh init` writes the line commented out
- `agent_env` (default empty): variable names, separated by spaces, that every agent gets with the values of the session that starts it, such as a provider's key (§ Building, **The agents' environment.**)
- `TEST_FILE_TIMEOUT` (default `600`; not a `swarm.sh config` key, an environment variable of `scripts/test.sh`, which `make test` runs): a whole number of seconds a test file may run. Past it, `test.sh` stops the file's process group (TERM, KILL after 2 s) and fails it as `TIMEOUT <file> after <n>s`, printing its last 20 lines and appending a `reap` line to `.swarm/events.tsv` (see the audit log). A file in the Makefile's `SLOW` gets three times the limit. Anything but a whole number of 1 or more is refused. `SWARM_SLEEP_SCALE` defaults to `0.01` in `test.sh`, as in the Makefile. `test.sh` unsets every other `SWARM_*` variable, so a test never sees the `SWARM_PROJECT` that points a builder's pane at its real project. It also sets `SWARM_NO_CI_REFRESH=1`, and dash starts no detached ci refresh while `SWARM_SLEEP_SCALE` is set. Each file runs from its own `TMPDIR`, outside any git repo, with `SWARM_PROJECT` naming a stand-in project of the job's own; `tests/test_helpers.sh`, which every test sources first, drops it, and a file whose `swarm.sh` still reaches the stand-in fails, naming what it left there. A `swarm.sh` call a test leaves unpinned (no `cd` into its project, no `SWARM_PROJECT`) stops at "not in a swarm project" instead of reaching the checkout's `.swarm` logs. `MAKEFLAGS`, `MFLAGS` and `MAKELEVEL` are unset for the file, so a `make` a test runs starts clean. `SWARM_FORBID_PROJECT` (set by `test.sh` and by `tests/test_helpers.sh` to the checkout the tests run from, its main checkout from a worktree) names a project `swarm.sh` refuses to act on, named directly or through a worktree of it, with `SWARM_FORBID_PROJECT: <dir> is the checkout the tests run from, or a worktree of it`, so such a `swarm.sh` call stops before it writes; the hooks' own event lines (`hooks/merge-guard.sh` `record`, `hooks/lead-stop.sh` `log`) are not `swarm.sh` calls and are not covered

## Cleanup, escalation and session logs

Every agent is a full Claude Code session, on a model chosen by its role, and planning one epic
on the full path (not the small path, which starts none, nor a split, which starts a split-critic) starts four agents, plus up to five skeptics, one per `risk: high` story, and two more surveys for a multi-repo epic. Agents use your own `claude`, `codex`, `gh` and `git` logins and never
touch real cloud or credentials. By default no agent merges unless an HLD grants `merge`; with `merge = agent` each
story's review agent merges that story's own PR, and no conductor merges one.

When `swarm.sh close` closes the builder of a code, docs or chore story that is still `ready`, it
counts a failed build in the story's `attempts:` and clears the attempt away: its worktree and its
`story/<slug>` branch here and on origin. While the story's PR is open it does neither: it closes the
builder alone and puts the story in review with the PR, unless it is `swarm.sh close <slug> --drop`,
which also closes the PR unmerged and prints the head SHAs it dropped. `swarm.sh reconcile`
removes the same worktree and branches once a story's PR merges, closing its builder first if it is
open. When a PR closes unmerged, it removes them only if no builder is open. That leaves nothing to
clean up by hand, unless reconcile prints `build kept: <slug>` or `build cleared: <slug>`, which say
what is left. A story that has failed
twice is rebuilt on Fable, the most expensive model. This ships on as `escalate_after = 2` in `.claude/swarm/config`;
`escalate_after = 0` turns it off. If the Fable build fails as well, the story becomes a `lead`
story and the lead decides: it re-scopes the story and runs `swarm.sh reset <slug> <reason>` to build
it again (once per story), or drops it. Then it tells you what it chose and why. A Fable build
can stop to ask your consent to spend usage credits. The conductor accepts it for you, so a third
build can spend Fable usage credits. `swarm.sh dash` shows who is on call, how many builds
escalated today, which attempt each Fable builder is on, and each escalation step in the recent panel.

### The escalation ladder

A step-up keeps the work done so far, where `escalate_after` clears a failed attempt away and the
next build starts from the base. With `escalate_ladder = sonnet,opus,fable`,
`swarm.sh step-up <slug> <trigger>` closes the story's builder without counting an attempt and starts
the ladder's next model in the same worktree and on the same `story/<slug>` branch, with any open PR
left as it is. The trigger says why: `findings-<step_up_findings>` (that round of review findings; the label follows the value, so it is `findings-3` at the default of 3 and `findings-2` with `step_up_findings = 2`), `ci-red-2` (CI
red twice), `stalled`, or `no-pr` (the builder stopped with no PR). The build is the newest
agents.tsv line for its builder, and the next model is the ladder's first one above that build's
model, so a chore on Haiku steps to the first rung. The new builder keeps its build's role family. On
the escalate role's model (Fable) it runs as `escalate`. Otherwise a code build runs as `code-sonnet`
on Sonnet and as `code` on Opus, and a docs or chore build keeps its role, and that role's effort, on
the new model. `escalate_ladder` changes nothing about `escalate_after`: a step-up counts no
attempt, while a close that counts a build as failed raises `attempts:` and clears the build as
before, and the next `swarm.sh story` build is on Fable once `attempts:` reaches `escalate_after`.
The Fable rung is an `escalate` build, though, so a close that counts it as failed hands the story to
the lead, as after any failed escalate build, whatever `attempts:` says.
Nothing is closed when the ladder is empty, when the build is at or above the ladder's top rung, when
the story is not `ready`, not of a kind an agent builds, held for review as a stacked child
(`held_by:`), or has no worktree, when a PR on `story/<slug>` has merged or is set to auto-merge (the
build is done, as `close` also judges), when gh cannot list those PRs, when its `env:` names a
variable not set here, or when the build's role is one nothing starts now (a past `verify` build).

The old builder is closed first, since the new one takes its name, and only then is the handover
brief written, so it holds everything the old builder did. If closing it left a git step unfinished
in the worktree (an `index.lock`, or a merge, rebase, cherry-pick or revert in progress), step-up
stops and names it: finish or abort it there, then resume. If the start fails, step-up stops at the
step that failed, with that step's message, and logs nothing as an escalation. A builder's
brief is sent at most twice, and a Fable builder, which at xhigh can take longer to start, gets 300
seconds over both tries to show it took it (150 for its one try when it has no Claude session to
read yet, see `tell`); `SWARM_PROMPT_TIMEOUT_MS` overrides that.
When a new rung's brief may have gone out but still reads as not taken up, or unsure, or herdr sent
it once and did not show the turn start (the start's warning), step-up keeps
its pane, warns, and reads it once more over 300 seconds, then says `took up its brief after all`
if it did. A builder blocked on a question before its brief went is not read again. If herdr gives
no status for it during that read, step-up stops and keeps its pane and agents.tsv line: look at it
with `herdr agent read <name>` before you resume. One still idle
with no turn after that, or gone, has not started: it is closed and loses its agents.tsv line, so
the rung is on record once, when it starts. The worktree, branch and step-up marker are kept, and
`swarm.sh step-up --resume <slug>` writes the brief afresh and starts the rung once the cause is
fixed. A resume that starts logs the step-up and sends the `/goal` as step-up would have.

The new builder's brief is the usual one with a handover after it. The handover says why it took
over, and gives the story as the board holds it, since the last builder may have deleted the file
from its worktree. Next comes the diff: committed and uncommitted changes and untracked files, from
the build's merge-base with the base, so the base's newer commits are not in it. It stops at 400
lines, and the fence around it is longer than any run of backticks inside it. For a story stacked
on parents whose PRs are still open, the diff starts at their branches instead, and the handover
carries build_story's `Merge after <PRs>` note. When a parent's PR has merged (squashed, its commits
are on the base under other ids), the diff is of `origin/<base>` to the branch as if the base were
merged in, and the handover says to merge it in before pushing. If that merge would conflict, the
diff stays the one from the merge-base, with the parent's commits in it, and the handover says to
merge the base in and resolve it first. Then comes the review agent's review file,
`.swarm/reviews/<slug>.md`, pasted only when its `head:` line is the branch's HEAD; it holds a pass
or a stop, since the findings to fix go to the builder by `tell` from `.swarm/reviews/<slug>.round.md`,
and a step-up in place of a findings `tell` pastes that tell's file. A review file of an older head
may be stale, so the handover only names it. Last come the open PR's
failing checks. With none listed, it says that none are failing, that the PR has no checks
reported, or that gh could not read them. The handover also tells the builder to put a `Models:` line in the PR body naming
every model that worked on the story, in order.

You rarely run `step-up` yourself: with the ladder set, swarm.sh runs it on each trigger as it sees
it. A build here starts at the story's newest `story`, `escalate` or `agent` start.

- `close` steps up a builder it closes with no PR (no cause, `met` or `bound`) instead of counting
  an attempt.
- `wait --stall` steps up a builder it finds stalled, and prints `stepped up:` in place of
  `stalled:`.
- `tell <slug> findings` steps up a builder on its `step_up_findings`-th findings of the build (the third by default) or any after, and
  does not send them: they go into the handover brief, and the tell fails, saying so. The count is
  per rung. It runs from the build's newest start, and a step-up is a start, so at the default of 3
  each rung below the top is sent 2 findings rounds and steps up on the third. The top rung follows
  `top_rung_rounds` instead (below). An earlier
  tell counts when it went through, or when herdr sent the findings but the builder was not seen
  taking them up. That tell fails and says what to do. When the builder may or may not have the
  findings, do not send them again. When herdr read it idle with no turn after both tries ("not
  taken up"), read its pane, and if they never arrived send them again as `tell <slug> nudge`, which
  is not a round. One herdr never sent, or whose reply could not be read, does not count. Instructions
  that are not review findings, such as a stacked child's merge, go as `tell <slug> nudge`.
- `tell <slug> findings` holds the story for the lead when its builder is on or above the top rung,
  where no step-up is left, and the tell would be the `top_rung_rounds`-th findings round there (the second by default) or a later one (the
  block, the `held` line and the tell's message name the round). The rounds count from when
  the builder reached that rung, or from the build's start when it began there (an `escalate_after`
  Fable build, or the top of a two-rung ladder), or from the lead's last `reset` of the story,
  whichever is latest. The findings are not sent and the tell fails, saying so. The story turns
  `kind: lead` with `held_for: top-rung`, logged as `held`, and its block holds the findings, which
  are also kept in `.swarm/briefs/<slug>.held-findings.md`. The builder and its PR are kept. The lead
  narrows the scope, splits the story or accepts the PR with follow-ups, then lifts the hold with
  `reset` (which keeps `attempts:` and is not the story's one reset) and sends that file with
  `tell <slug> findings`; that tell counts like any other, so a later round holds the story again. Or
  the lead drops the story: `drop` leaves the builder, PR and worktree, so the block says how to close
  them first. A tell to a story already held is refused. A hold that fails after its block is written
  fails the tell, and the findings are not sent. Where a
  step-up would be refused (the story is not `ready`, is a held stacked child, or has a PR merged or
  set to auto-merge), nothing is held and the findings go as usual.
- `watch --epic` or `--backlog` steps up a story of its own whose builder is open, once the PR has
  gone red on two heads of the build. Every head it sees goes into `.swarm/red-heads.tsv`, and each
  is judged again on later polls until `ci_gate` calls it red or green, even after a new push. A
  head committed before the build started is not counted: a head's time in that file is its commit
  time (the committer date GitHub holds, read when the head is first noted; the scan's own time when
  that read fails), so a head the rung before pushed stays that rung's however late a scan first
  sees it. The lead's bare `watch` steps up nothing.
- `wait-pr` runs the same check when it ends red in the story's review pane, `review-<slug>`'s by
  the record `merge` and `tell` go by (its tab record, its role in `.swarm/agents.tsv` and herdr's
  list). The `<slug>` comes from the PR's `story/<slug>` branch, and the PR must be in
  the story's own repo. The review agent's own waits then count the red heads even when no watch is
  running. A `wait-pr` from the builder's pane or the lead's counts nothing and writes nothing to
  `.swarm/red-heads.tsv`, and so does one on a story whose repo cannot be read, which `wait-pr` says
  on stderr. Nor does a red on a head the builder had already replaced by the time `wait-pr` ended
  (the PR's head may be green by then), nor one on a story with `env:` names, which the review agent
  does not have, so a step-up from its pane would be refused and would stop the watch's on that head
  too: such a story is left to the watch. A watch and a review agent can both check one PR: each head counts once, however many
  of them judged it, and only one step-up of a story runs at a time. The scan runs in a swarm.sh of
  its own under `wait-pr`'s deadline, so a read that hangs still ends there; a step-up it started is
  killed with it at that deadline, and the lead's exit is then `step-up --resume`, as for any
  step-up killed partway.

Each prints `stepped up: <slug> ...`. The conductor's brief tells it to wait on that builder
again, not to close, retry or tell it; the review agent's brief has it stop with `head moved: stepped up: ...` after one from `wait-pr`, which the conductor's brief reads as a step-up to wait on, not a head to review again. A close that a step-up replaced logs no close: the escalate
line ends that build. One step-up of a story runs at a time, under `.swarm/locks/step-up-<slug>`, which a
top-rung hold and `swarm.sh restart` take too. No step-up is tried at the top rung or off the ladder, so the command
carries on as it would with the ladder empty, apart from the top-rung hold above. A step-up that is refused, or fails before it closes the builder, says why on stderr,
logs nothing (a refusal is no sign of life), and leaves the command to carry on the same way. `watch`
does not try it again on the same head. A step-up whose new builder does not start, after the old one
closed, prints `step-up failed: <slug>` and stops the command that ran it: a close counts nothing
and clears nothing. The story is then the lead's to resume (`step-up --resume`), and no trigger tries
that build again meanwhile. `wait --lead` tells the lead within one poll (§ The lead), so the
conductor leaves the story alone. The failed step-up also sends the story's conductor
(`conduct-<epic>`, or the backlog's) a note through `swarm.sh tell <conductor> note`, logged as
`tell:note`. Its first line says swarm.sh sent it, since the lead may not know yet. It names the
story, why the step-up failed and `swarm.sh step-up --resume <slug>`. A conductor whose turn has
ended is prompted to read it. When a review agent's `tell` ran the step-up, the note is how the
conductor hears of it, since that output goes to the review agent's pane. Nothing is sent when herdr
lists no conductor of the project, when the conductor has written its report, when the step-up was
refused inside the close, or when a `step-up --resume` fails, since the lead ran that. Reading
herdr's list and sending the note get 120 seconds between them. Past that, or when the list cannot
be read, the step-up prints a warning and ends as it would have.

A step-up is logged as `escalate` with `ok (<trigger>: <from> -> <to>)`. Only a step to the
escalate role's model starts an escalate build, so `outcomes` pairs only those (and build_story's
`ok (attempt N)`) with an escalate build, and `dash` counts only those among today's escalations. A
Fable builder that got there by a step-up shows `from <model> · <time>` in `dash` where a third
build shows its attempt, and `dash` times each rung from its own step-up. In `outcomes` a
target's step-ups, in order, take its builds in agents.tsv order. The rungs of one build are one
attempt, and each replaced build has a close, with the cause `step-up:<trigger>`.

`swarm.sh close` keeps a copy of each closed agent's session log in `.swarm/sessions/`, because
Claude Code deletes them after 30 days. The copy is not redacted, so it can hold secrets the session
saw. Only your user can read it, and `.swarm/` is git-ignored, so it never leaves your machine.
Flow's `cost` section and `outcomes` read the copy once the original is gone.

## Commands

| Command | What it does |
|---|---|
| `swarm.sh step-up <slug> <trigger>` | Close a struggling build and start the next model in `escalate_ladder` on the same branch, without counting an attempt. `<trigger>` is `findings-<step_up_findings>` (`findings-3` by default), `ci-red-2`, `stalled` or `no-pr`. `swarm.sh step-up --resume <slug>` starts a rung whose start failed. `close`, `tell`, `wait --stall`, `watch` and a review pane's `wait-pr` run it themselves. Refused while the ladder is empty ([§ The escalation ladder](reference-models.md#the-escalation-ladder)). |

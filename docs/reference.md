# Reference

The detail behind [the guide](method.md): how each step works, every rule and every log. Read the guide first.

## The lead

The lead's messages to agents go through `swarm.sh tell`, which logs them as `tell:<kind>`, never a
bare `herdr agent prompt`.

When the board is in the project's repo, the lead's board edits (a re-scope, a new story, an
unblock) go through `swarm.sh board-pr`, each in its own worktree, never the main checkout. A board
outside the repo is edited where it is, and `board-pr` refuses it.

- `start <name>` makes `<repo>-wt/_board-<name>` on a new `board/<name>` branch from `origin/<base>`
  and prints its path. The `_` keeps it apart from story worktrees (`<repo>-wt/<slug>`), since a
  slug never has one. It refuses when the branch exists here or on origin (or origin cannot be
  read), when the directory exists, when the path resolves into the main checkout (through a
  symlink or `..`), and when `git worktree add` fails.
- `open <name> "<title>" <body-file>` refuses unless every changed file is under the board. Otherwise
  it commits with the brief's commit trailers, pushes, and opens the PR, printing its URL. A trailer
  is found anywhere in the brief, quoted in a sentence too: a `<Word>-by:` token, a name (with a
  letter, and no colon or quote), and an email in `<...>`. A placeholder such as `<who> <email>` is
  skipped, and the prose before a trailer never becomes part of it. Run `open` again to push
  more edits: it prints the open PR's URL and opens no second one. Once the branch's PR has merged
  or closed (squashed or not), it refuses, since the branch still holds the merged commits: run
  `done`, then `start` again. A PR counts as the branch's when its head came after the branch was
  started (the first entry in its reflog), so one from an earlier use of the name does not.
- `done <name>` removes `board/<name>` on origin, then the worktree and the branch here, once the PR
  on the branch's tip (the local one, or origin's when there is none here) has merged or closed. A
  PR left by an earlier use of the name does not count. With no PR it removes an abandoned start:
  a branch with no commits past the base. It runs every check before it removes anything, and
  refuses while any PR on the branch is open, when origin cannot be read or its branch has moved
  past the local one, when the worktree at that path is not on `board/<name>`, has uncommitted
  changes or is locked, when `board/<name>` is checked out anywhere else (the main checkout, or
  another worktree), and when git cannot remove the worktree (giving git's reason). Origin's
  branch goes first, so when its delete fails the local state is still there for the next run.

Each step logs one `events.tsv` line, `board-pr:start`, `board-pr:open` or `board-pr:done`, with
the name and `ok` or the refusal. The name may be a story's slug, so these lines are never a sign
of life for that story's builder.


**The lead is woken when its queue grows.** While a conductor works, `/swarm-dev:swarm` waits on it, and
`swarm.sh next` names that conductor first. A story held or escalated mid-epic would sit unseen
until the conductor reports; on 2026-10-16, three held stories waited two hours that way. So the
lead also runs `swarm.sh wait --lead` beside the conductor's wait. Every 30 seconds
(`SWARM_LEAD_POLL`) it reads the board, and it returns as soon as a new item appears: a held story
(`held_for:`), an escalated one, or a story or epic in review whose PR heads are all green and that
waits on the lead's user: every one with `merge = human`, and with `merge = agent` only a PR
`swarm.sh merge` holds for them (§ Merging). It prints one line per item and logs one `lead-woken` line for each in events.tsv.
The lead handles each line at once and starts it again. It keeps what it last saw in
`.swarm/lead/seen`, so an item that lands between two runs wakes the next one. A new run stops
any earlier one, so only one is ever watching. It never nudges an agent and never edits the board.

## Writing an epic

Everything starts here, and it is the one stage you do by hand: the epic decides what every story
and line of code after it is for, so you write it with a co-author.

1. **Start it.** In your Claude session, inside herdr: `/epic <title>`, for example
   `/epic Add rate limiting to the API`. This creates `docs/epics/<slug>.md` with `status: draft`
   and opens a new pane (tab `epic`) with a co-author on the most capable model. Your session only
   supervises from here.
2. **Write it in the co-author's pane.** Switch to that pane and talk to it there. It reads the
   code, the ADRs and `AGENTS.md` first, then asks you the questions that decide the epic, one or
   two at a time, and writes your answers into the file section by section, citing evidence. It
   does not invent requirements, commit, or change `status`.
3. **Say it is ready**, to the co-author, in the same pane. A reviewer (the `epic-review` role, the
   most capable model at `xhigh` effort) starts on its own and attacks the draft: a problem with no
   evidence, goals that cannot be checked, an epic that contradicts an ADR or a safety rule, unnamed
   risks, open questions that would block planning it into stories. Its findings arrive in the
   co-author's pane; go through them there and revise until you are satisfied. You never switch
   tabs.
4. **Agree it**, to the co-author. Your session, waiting in the background, sets `status: active`,
   opens a PR for the epic (reviewed like any other change), and closes the co-author's pane. Only
   you can agree an epic; no agent changes its status, and `next` plans no draft epic.
5. **Hand over.** Run `/swarm-dev:swarm`. It sees an active epic with no stories and starts
   `/plan-epic`.

**What a good epic has.** Four sections: Problem (with evidence), Goals, Non-goals and
Constraints, and a **Your part** line. **Goals** are its **Done when**: checks that could fail,
because the conductor stops when they hold. **Non-goals** keep the plan from growing.

**Stopping and resuming.** The epic is a file, so nothing is lost if you stop: run `/epic` on its
own (or `/swarm-dev:swarm`, which sees the draft) and a new co-author picks up the draft in progress
from the file; if there are several, it asks which. With no draft at all, it tells you where the
chain stands instead.

## Model and effort

Every agent's model and effort come from its role, set in one place: `policy()` in
`bin/swarm.sh` (`swarm.sh policy <role>` prints it). Spend on judgment, save on reading:

- **Design is Fable.** An epic is co-written at `high`, because the user waits on every turn, and
  attacked at `xhigh` before it is agreed.
- **Judgment is Opus.** An epic's decomposition into stories runs at `xhigh`. Skeptics and the
  critic run at `high`, because a skeptic is the only gate a story passes before it is built.
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
  failed build of a code, docs or chore story. When the story is still `ready`, its builder is still open and no PR on `story/<slug>` has merged or is open with auto-merge set, it raises
  `attempts:` by one and clears the attempt away: it removes the worktree and `story/<slug>`, here
  and on origin, and closes each open PR unmerged with a comment naming the attempt. The next build
  then starts fresh, and the third runs on Fable. A close after `review`, after a merge or after
  the builder has gone counts nothing, and `reconcile` sending a story back to `ready` never
  counts. If gh cannot list the PRs, the close counts and clears nothing and says why on stderr.
  `swarm.sh close <slug> <cause>` also says why the builder stopped: `met`, `stalled` and `bound`
  count as above, while `impossible`, `paused` and `cleared-on-error` are not attempts and leave
  `attempts:` as it was. `impossible` clears the build away whenever it hands the story on (below).
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
  them), it runs no `gh pr close`, but deleting `story/<slug>` on origin makes
  GitHub close any PR still open on that branch. The block then says the PRs were not listed, so the
  lead looks before resetting. Any other story, and a name with no story file, is refused before
  anything closes.
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
  Code's logs into tokens and estimated cost per role. The lead's own sessions count too, under
  `lead`: every session in the project's Claude Code directory that agents.tsv does not name. Change
  `policy()` from that table, not from a guess.
- **The conductor is Opus at `high`, one fresh session per epic**, on the standard context window,
  never 1M. A conductor re-reads its whole context every turn: on the project this came from, one
  long-lived lead session was 80% of all tokens over three days (3.6B of 4.5B, at up to 1M
  context). The board carries the state, so a new conductor costs little.
- **A review agent is Opus at `high`**, the model the conductor reviewed with before each PR got its
  own (role `review`, started by `swarm.sh review-agent`). One per green PR, so reviews run side by
  side and the conductor's own context holds only the findings files.
- **The fallback reviewer runs on the model `fallback_reviewer` names, at `high`** (role
  `review-fallback`). codex-review starts it only when codex hits its usage limit and the key is set.

## Settings

The table in [the guide](method.md) lists every key. The rules the table leaves out:

- `merge` (default `human`): `human`: no agent merges, and a green, reviewed PR waits for you (§ Merging). `agent`: the conductor merges, except a PR `swarm.sh merge` holds for you (§ Merging)
- `lessons_file` (default `.claude/swarm/brief.md`): where adopted lesson rules live: the brief, `AGENTS.md`, `CLAUDE.md` or `.claude/CLAUDE.md`, the files every agent reads (any other is refused, since a rule there would retire its candidate without reaching anyone). With `AGENTS.md`, rules about writing code reach you and interactive sessions too, and the brief keeps the swarm-only rules. Every brief still gets the file's tagged rule lines (only those), since a builder in another repo's worktree reads that repo's `AGENTS.md`, not this one. The 4 KB cap measures what every prompt carries: the brief plus `lessons_file`'s tagged rule lines; the rest of `AGENTS.md` is not capped
- `stall_minutes` (default `30`): a story's builder that is working this long with no sign of life (no commit in its worktree, no edit there to a file `git status` lists, no update to its PR, no swarm action on its story) is `stalled?`: `wait --stall` returns on it. `dash` shows every working agent's time since its last sign of life after its state (`working 12m`); past this it shows `stalled 40m` instead, marks the agent `!` and lists it under needs you (with `lead = session`, under the lead's queue). An agent with no story (a conductor or planner) has its own `events.tsv` lines as signs: those naming it, and once it has a start line, those its pane ran, nudges, incidents and failed tells excepted. Any agent with a Claude session, builder or not, also counts the last write to its session log (`.jsonl`), which the session makes on every turn and tool call. Working is its Claude session reporting busy, for `wait --stall` and `dash` alike, and herdr's working for a codex builder
- `sonnet_share` (default `0`): `N`: one in N `kind: code` stories marked `easy: true` and without `risk: high` is built on Sonnet (role `code-sonnet`), so `swarm.sh outcomes` can compare it with Opus. The pick is the `cksum` of the slug mod N, so a slug always gets the same model. Only a story's first build is picked: a retry is built on Opus, or on Fable once `escalate_after` applies. `0` is off (§ Model and effort)
- `escalate_after` (default `2`): `N`: a story an agent builds whose `attempts:` has reached N is built on Fable (role `escalate`), whatever its kind, risk or `sonnet_share` pick. An absent `attempts:` is 0, and a value that is not a whole number is refused. `0` is off (§ Model and effort)
- `builder_subagent_model` (default empty): a model such as `haiku`: the agents that build a story start with `CLAUDE_CODE_SUBAGENT_MODEL` set to it and `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`, so their subagents (an Explore search, say) run on it. Planners and conductors are unchanged. Empty leaves Claude Code's choice
- `goal` (default `off`): `N`, such as `goal = 5`: `swarm.sh story` writes each builder a goal condition beside its brief, in `.swarm/briefs/<slug>.goal.md`. It refers to the story by the path its brief gives (relative to the worktree when the board is in the repo it builds): every item under **Done when** and **From review**, if any, holds. Then it adds the reply the brief asks for, a way out (reply `IMPOSSIBLE: <why>` and stop) and `or stop after N more turns`. Claude Code queues a long paste as a prompt instead of running it as `/goal`, so a `/goal` message over `GOAL_SEND_MAX` characters stops `story` before it makes a branch or worktree. Needs Claude Code 2.1.269 or later. Once the brief is taken up, `story` sends the builder the goal and fails if its session log does not show it set (§ Building, **The goal.**)
- `codex_minutes` (default `10`): `swarm.sh codex-review <base>`, which every brief and the lead use to run codex's review, stops codex after this many minutes: TERM to its whole process tree, a few seconds' grace, then KILL to whatever is left. It then prints `codex skipped: timed out after <N> min` and exits non-zero, and its events.tsv line says the same. It ships on (§ Scoping an epic)
- `fallback_reviewer` (default empty): a model such as `sonnet`. When codex reports a usage limit, `codex-review` starts a review agent on it in codex's place (role `review-fallback`), waits for its findings and prints them in codex's form. Empty keeps `codex skipped: usage limit`. § Building has the details
- `lead` (default `off`): `session`: a lead session acts for you, so `dash` splits needs you in two. Needs you keeps only your steps: a story with a **You:** step and an expired login. Every merge row (with `merge = agent`, a `costs: money` merge row stays under needs you), an agent waiting on a prompt, a `lead` story with no **You:** step, every escalated story, an empty pane, an agent whose session is gone or unknown, and a stalled agent go in a `lead's queue` box under it, left out when empty. `next` and `status` are unchanged
- `merge_admin` (default `off`): `on`: `swarm.sh merge` passes `--admin` to `gh pr merge`, so it merges in a repo whose ruleset requires an approving review, which no agent can give. It does so only after the checks it always makes: the head is green, no `costs: money` hold applies, the `--board` or `--release` scope holds, and the head is the one `--head` names. `--admin` skips every rule on the base, not only the review, so `swarm.sh merge` first reads the base's rulesets and branch protection itself. It refuses while a status check they require is absent from the head, while they require the branch up to date (strict) and the head is behind the base, and whenever they hold a rule besides the review, the status checks and rules about pushes (deletion, force pushes, creation): a merge queue, required workflows, signatures, linear history, conversation resolution, deployments, code scanning or push restrictions. That includes the review rule's own thread resolution, and merge methods that leave out the one `swarm.sh merge` picks from the repo's settings. A classic protection field outside the few known to be safe is refused whatever its name, and a 404 from branch protection counts as unprotected only when GitHub says `Branch not protected`, since a token that cannot read protection gets a 404 too. The refusal names the rule. A red head, a held PR or a moved head is still refused before `gh pr merge` runs. Off, `swarm.sh merge` never passes `--admin` and reads none of these

## Scoping an epic

An epic (`docs/epics/<slug>.md`: goal, **Done when**, out of scope, constraints) becomes stories
with `/plan-epic <slug>`. An epic of at most 3 stories with no `risk: high` is planned by the lead
alone, with one codex pass over stories committed in a board-PR worktree. A large one (more than 8
stories, or goals that can ship apart) is split by the lead alone into child epics, each with
`parent: <epic>` and its own **Done when**, planned in turn; the parent becomes `status: split` and
counts as done once none of its children is left. Any other epic gets one survey agent unless its text names another repo (three
then), one lead decomposition into one-PR stories with `kind`, `touches` and `depends_on` (a
chain at most 3 stories deep, and a story's scope opens with what it needs from each `depends_on`),
and a skeptic per story (capped at five, the rest logged), a codex pass and a critic, all in
parallel. `risk: high` goes only to real-cloud, teardown, credentials and safety paths. Agents write their answers to
`.swarm/<epic>/`. The user sees refuted stories, contradictions, the risky stories and stories ÷
longest chain first, and approves before the board PR opens; review fixes are folded into
each story's scope. Once the board PR is open, each skeptic, codex and critic finding is logged
against it with `log-finding --reviewer <who>`, declined ones with `--declined <reason>` too. A full run is about ten agents, so
scope deliberately.

**Ship code switched off.** Code that adds a flag or setting merges with it off, so the merge
changes no behaviour; a separate `lead` story turns it on. Bundled, a failure cannot say whether
the code or the switch broke it, and the rollback has to undo both. Two exceptions:
`escalate_after` ships on, at `2`, by the user's decision of 2026-10-13. It changes nothing until a
story has failed twice. `codex_minutes` ships on, at `10`, because without a limit a codex review
can hang for good.

A story's **Done when** names what the builder's session can show (a test run, a command's output, a file), never something only the conductor or a merge can show, so a goal's judge can see it.

## Building

`swarm.sh conduct <epic>` starts a fresh conductor that drives the epic's stories to merge, then
stops and reports; the session it was started from stays free. Its last act is writing that report
to `.swarm/conduct-<epic>.report.md`, and that file, not the agent going idle, is how
`/swarm-dev:swarm` knows it has finished: a conductor is idle whenever it waits on its own
background work. When it starts, an epic still `later` is set `active` (in
`.swarm/board-state/epics/<slug>`, which `conduct` reports in one line), so `status` and `next`
stop listing it as waiting on you. It runs in a herdr workspace named for the epic's `parent:` if it has one (epics with the same
parent share it), or else for the epic, in a tab named for the epic, in a pane named `conductor`. Each story it starts gets a pane in
that tab, named for the story; a tab holds four panes, and the fifth opens `<epic>-2`. A one-off
story gets a tab of its own. Conductors of different epics can run side by side (each watches only its own epic's PRs, with
`watch --epic`), as long as their stories touch different files; shared files are the lead's alone.

**The backlog conductor.** `swarm.sh conduct --backlog` starts `conduct-backlog-<dir>-<hash>` (the
first 9 characters of the project directory's name, then 6 hex characters of a checksum of its path), which builds the ready stories with no `epic:` (the one-offs) the way an epic's conductor builds an epic: waves with
`story --strict`, the same review, and the same handover or merge. It runs in a workspace named
`backlog` and needs no epic file; a board with an `epics/backlog.md` makes it refuse. herdr's agent
names span every project, so naming it for the project's path lets two projects each run one at once,
even two directories with the same name. A name another project's agent holds is refused before the
old report or brief is touched, and the refusal says where that agent runs. An epic whose
conductor would take that name (`backlog-<dir>-<hash>` for this project) is refused too. It watches only
its stories' PRs (`watch --backlog`), and a story whose worktree already exists has started, so it
waits on that builder and never starts the story again. Its report,
`.swarm/conduct-backlog.report.md`, lists each one-off it could not start as
`not started: <slug> (<why>)`. With `merge = human`, a story refused because another of its
one-offs is in review is reported as `not started: <slug> (waits on <other>'s merge)`, since that
merge cannot happen while the conductor runs. `/swarm-dev:swarm` runs it for a `story` or `resume`
step. Until a story or epic is added, changed or removed under `stories/` or `epics/` (a merge
removes one), it starts no new backlog conductor while that report exists, whatever the report
says, and tells you why the story waits. For a `resume` step it also stops when the report lists
the story under `not started:` (a build that died), even after the board changes. If story/<slug>
has commits worth keeping (`git log origin/<base>..story/<slug>`), push it and open a PR from it.
Otherwise clear the stop by discarding the build from its repo
(`git worktree remove --force ../<repo>-wt/<slug>`, `git worktree prune`,
`git branch -D story/<slug>`, and `git push origin --delete story/<slug>` if it was pushed), then
deleting `.swarm/conduct-backlog.report.md`. A fix that touches no story or epic, such as a code PR
that turns CI on the base green, does not clear the stop either: once the cause is fixed, delete
`.swarm/conduct-backlog.report.md`.

**The agents' environment.** herdr starts each agent in a pane's shell, which holds everything you
exported. Before the agent starts, swarm.sh has that shell replace itself, through `env -i`, with
`zsh -f` (no rc file runs) holding only:

- `PATH`, `HOME`, `TERM`, `USER`, `LOGNAME`, `TMPDIR`, `LANG` and the `LC_*` variables;
- where logins, config and logs live: `CLAUDE_CONFIG_DIR`, `CLAUDE_PROJECTS_DIR`, `CODEX_HOME`,
  `GH_CONFIG_DIR`, `GIT_CONFIG_GLOBAL`, `GNUPGHOME` and the `XDG_*` directories;
- the session bus, `DBUS_SESSION_BUS_ADDRESS`, through which `gh`'s keyring token and
  `git-credential-libsecret` reach the Secret Service on Linux;
- for a push: the ssh agent's `SSH_AUTH_SOCK` and `GIT_SSH_COMMAND`;
- for a proxy or an intercepting CA: `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY` and their lowercase
  forms, `SSL_CERT_FILE` and `NODE_EXTRA_CA_CERTS`;
- which provider and model Claude Code uses: `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`,
  `CLAUDE_CODE_USE_FOUNDRY`, `ANTHROPIC_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`, `AWS_REGION`,
  `AWS_PROFILE`, `CLOUD_ML_REGION` and `ANTHROPIC_VERTEX_PROJECT_ID`;
- swarm.sh's own `SWARM_*` settings, with `SWARM_PROJECT` as the project's absolute path, so the
  agent's own `swarm.sh` finds the same project and settings from any directory;
- `SHELL`, set to that zsh; `ZDOTDIR`, set to the agent's own `.swarm/zdotdir/<agent>`; and
  `GPG_TTY`, set to the agent's own terminal, so pinentry asks there and never in yours. swarm.sh
  makes the `ZDOTDIR` afresh, 0700, at each launch, with only a `.zshenv` and a `.zprofile` that
  put back the `PATH` a login shell was given once `/etc/zprofile` has run (on macOS, its
  path_helper puts `/usr/bin` and `/bin` first), and removes it when `swarm.sh close` closes the
  agent;
- `HERDR_ENV=1`, and those of herdr's own variables for the pane that the pane has.

The others take swarm.sh's value, when it has one, except herdr's, which come from the new pane. A
story's `env: [NAME, ...]` adds those names for its builder, whether `story` starts it or a conductor
restarts it with `swarm.sh agent`. A conductor gets the names of its epic's open (`ready`, `blocked`
or `review`) code, docs and chore stories (for `conduct --backlog`, those with no epic), so the
builders it starts can receive them; a `lead` story's names stay with you. A conductor has only the
names its stories had when it started: for a story added later with a new name, restart it with
`swarm.sh conduct <epic>`, which its refusal names. Each value comes from the session that runs
`swarm.sh`. `story`, `agent` and `conduct` refuse, before anything starts, an `env:` that is not a
one-line `[A, B]` list, a name that is not `[A-Z_][A-Z0-9_]*`, a name that session does not have,
and a reserved name: one from the list above or starting `LC_`, `SWARM_`, `XDG_` or `HERDR_`; the lead's
own Claude Code session's (`CLAUDECODE`, `CLAUDE_CODE_*`, `CLAUDE_PID`); and one that loads code
into what the agent runs (`BASH_ENV`, `ENV`, `DYLD_*`, `LD_*`). No value goes through a command line:
swarm.sh writes them to a 0600 file under `.swarm/launch/`, which the pane's shell runs and which
deletes itself, so the pane's scrollback shows the launch line with no value in it.

A login read from the environment does not reach an agent either: `ANTHROPIC_API_KEY`,
`CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, or a `GH_TOKEN` for `gh`. A story can name
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY` or `GH_TOKEN` for its builder (never a `CLAUDE_CODE_*` one), but
agents with no story of their own (planners and review agents, and conductors beyond their stories'
names) never get it. If you log in that way, log in through each tool instead: `claude` then
`/login`, `codex login`, and `gh auth login`. On Foundry, Bedrock or Vertex, the provider and model
selection above passes from the session that runs swarm.sh, or can go under `env` in
`~/.claude/settings.json`, which every Claude Code session reads. The credentials come from the
provider's own login or profile files (`aws sso login` or a profile in `~/.aws`,
`gcloud auth application-default login`), never from an exported secret such as
`AWS_SECRET_ACCESS_KEY`.

Because `SHELL` is zsh and `ZDOTDIR` is empty, every shell an agent starts later, such as Claude
Code's Bash tool and codex's commands, reads none of your `~/.zshenv`, `~/.zprofile`, `~/.zshrc`,
`~/.zlogin`, `~/.bashrc` or `~/.bash_profile`, even when your own shell is bash. Only the system
files in `/etc` (`zshenv`, `zprofile`, `zshrc`, `zlogin`) still run, and a login shell's `PATH` is
put back as it was given after them.

**Board state.** swarm.sh keeps the front-matter keys it writes (`status`, `prs`, `attempts`, `kind`,
`escalated_from`, `held_for` and `held_by`) out of tracked story and epic files. `review`, `unblock`,
`close`, `reset`, `reconcile` and `conduct` write them as `key: value` lines to
`.swarm/board-state/stories/<slug>` or `.swarm/board-state/epics/<slug>`, so a story and an epic with
the same slug keep separate state, and `git status` in the main checkout stays clean. Every command
reads a key from that file first and from the item's front matter second, so a key with no line
there, as on an existing board, reads from the file. `dash` reads its board rows the same way. A line
with no value clears the key, and swarm.sh writes no line that would only repeat the file's value.
Beside each line it keeps a `<key>@base:` line with the file's value at the time.
Once the file's value differs from that (a board PR set the epic `later`, say), the file's value is
read, and the next write to the item drops the old line. A write holds the item's lock, a
`<slug>.lock` directory beside its state file, so two commands writing one item at once keep both
changes; a command that finds the lock still there after 10 seconds stops and names it, as one
does when a state file cannot be read or written. The
escalated block `close` writes for the lead is in `.swarm/escalated/<slug>`. Deleting an item's file
where it is (`reconcile`, `finish` or `drop`, on a board outside the repo) deletes its state file
and escalated block too. `reconcile` also deletes them when an item's PR marked it `done`, and, on
a board in the repo, for each story or epic a commit deleted (its PR or a board PR), whether
reconcile pulled that commit or you did: the file is in neither `HEAD` nor the main checkout. A file
removed only by hand, or never committed, keeps its state.

**Pick the wave.** Only `ready` stories that do not clash. Two stories clash only when their
`touches` name the same `file:symbol` in the same repo, or when either names the bare file of a file
the other also names. Otherwise both build at once, even in the same file: git merges edits to
different parts of one file, and a story names the functions it changes. A builder whose PR
conflicts with its base merges its base in, resolves it, reruns the tests and pushes; a conflict
never sends a story back to `ready`. The conductor sends that as a `nudge` tell, which is not a
review round. It waits first for a builder that is working, and starts a builder in the story's
worktree when the one it had was closed after `swarm.sh review`.
Work that edits a shared file (`AGENTS.md`, root config, schemas, hygiene scripts) is done by the
lead, alone.

A wave only sees its own epic, so `story` also looks across epics. Before it makes anything, it
compares the story's `touches` with those of every story in another epic (a story with no epic
counts as another). If one of them is open (in review, or `ready` with its builder open) and touches the
same function or file, `story` prints `warning: <other> (epic <e>) is open and touches <entry>;
start <slug> after it merges` and starts the story anyway. `story --strict` refuses instead, naming
the other story, and leaves no branch, worktree, pane or brief behind. It also refuses when herdr
cannot list its agents or the board's `touches` cannot be read, where plain `story` warns that it
cannot tell. Then nothing is known to be open, so the message says to retry the story, not to wait
for a merge. `--strict` may come before or after the slug. Conductors always pass
`--strict`.

A `<file>:<fn>` entry matches the same fn in the same file, and a file-only entry matches anything
in that file. An entry with no `/` or `.` before its `:` names a fn in the previous entry's file and
repo, so `bin/swarm.sh:config defaults, CONFIG_KEYS` covers `bin/swarm.sh:CONFIG_KEYS`. When the
entry's own repo (its prefix, or the story's `repo:`) has a file of that name, it is that file
instead, so `Makefile` or `Makefile:lint` after another entry still matches. A `<repo>: ` prefix sets the entry's repo, and otherwise the
story's `repo:` does; the same file in another repo does not match. Parentheticals are dropped.

**Stacked builds.** A story need not wait for its parents to merge. `swarm.sh unblock` also readies
a blocked story that has no build yet (no worktree and no `story/<slug>`) when each `depends_on` slug
is finished or is an open story in the same repo with an open PR (in `review` with a `prs:` line, or
one that `gh pr list --head story/<p>` finds), and prints `ready: <slug> (stacked on <parents>)`. A
parent that is blocked, has no open PR or lives in another repo keeps the story blocked, and so does
a gh failure. A story that only an old build keeps from starting stays blocked too, printed as
`not stacked: <slug>` for the lead. `story` fetches each parent's branch and checks that its PR is still open. If one is not,
the story goes back to `blocked` and nothing is made. Otherwise the worktree starts at
`origin/story/<first parent>` with each other parent's branch merged in, events.tsv gets a
`stacked <slug>` line, and the brief says to open the PR against the base with
`Merge after <parent PR URLs>` in its body. A merge conflict fails, naming the two branches that
conflict and their files, and leaves no worktree or branch. The overlap check skips a story's own
parents and its own children, so neither holds the other back under `--strict`. While a parent is
still on the board, `swarm.sh review` holds the child: it sets it `blocked` with `held_by: <parents>`,
keeps its `prs:` line, builder, worktree and branch, puts nothing in review, and exits with
`held: <slug> waits for <p> to merge`, pointing at the child's Stacked line for what comes next. A held child still counts as open in the overlap check, since
its PR is. With `merge = human` the conductor then closes the child's builder with a bare
`swarm.sh close <slug>`, which counts nothing for a blocked story; with `merge = agent` the builder
stays open. When a parent's branch moves, the conductor tells the child to merge it in. A held child
is readied again only once every parent has finished, as `ready: <slug> (held: merge origin/<base>,
review again)` while its worktree is still there. With the worktree gone it is readied plainly,
without `held_by:` or the `prs:` line, and `story` builds it fresh. A parent squash-merges, so its
commits reach the base under new hashes: the child's builder (a new one in its worktree, when it was
closed) merges `origin/<base>`, and the child is reviewed again. `swarm.sh status` prints the same
instruction as the child's Stacked line, and the conductor acts on that line alone; a
`could not check` line there means nothing is known yet, never that the base is in. A review that
passes clears `held_by:`, and so does clearing the build (a counted, impossible, paused or
cleared-on-error close), which also drops the `prs:` line the hold kept. `story` refuses any story
whose worktree or branch already exists, and points a held one at its Stacked line.
Parents always merge first: you are never handed a child before its parents, and `swarm.sh merge`
refuses one too, since it merges only an item in review.

```bash
swarm.sh story [--strict] <slug>   # worktree on story/<slug>, a pane, the agent, its brief
swarm.sh wait <slug>       # in the background: returns when it settles
swarm.sh wait --until-report conduct-<epic>   # in the background: returns when the conductor reports
swarm.sh watch             # in the background: returns when a story PR needs the lead
```

`wait` returns when the agent's Claude session reports `idle`, `waiting` (printed with what it
waits on, such as `waiting: permission prompt`) or `gone` (its session has no entry in `claude agents
--json`, or one with no status: the process exited), which can be early. herdr's `agent wait` is only the wake-up, in
STALL_POLL_MS slices (a minute); after each wake or slice `wait` reads the session once, and never
herdr's word for it. A session Claude Code gives no state for (`unknown`, or the list call failed)
is waited on, said once on stderr. At the timeout `wait` prints the last state and exits 1, and so
it does at once when herdr's wait fails other than by timing out and the session has not settled.
A conductor is idle whenever it waits on its own builders, so `wait` on one holds until its report
exists, its session is waiting or gone, or its login expired. `wait --until-report`, which
`/swarm-dev:swarm` runs, does that with no timeout: an epic that takes more than an hour is not cut
short. It takes only a conductor's name and fails on any other.
A codex agent, or one with no recorded session, is waited on through herdr's status. A builder
whose session goes idle while its story is `ready` and has no open or merged PR (a closed one is an
earlier attempt's) has stopped early, perhaps on a failed request, and nothing else would wake it. `wait` tells it
why ("you are idle and story/<slug> has no PR") and waits again, up to three times. Nudges are at
least a slice apart unless the session turns busy in between. If herdr cannot deliver a nudge,
`wait` stops there and returns idle, and logs nothing for it. With `goal` on, `wait` nudges no builder, whatever its session log shows: a nudge would bury the reply and the goal entry the conductor reads the cause from, so `wait` returns idle and the conductor reads why it stopped. Only code, docs and chore stories are
nudged, never a conductor or a planner, and a gh or git call that fails counts as a
PR. An idle agent whose transcript (its session's `.jsonl`, the file flow's `cost` section reads) ends on Claude
Code's "Login expired · Please run /login", with no message sent to it since, is never nudged or
waited on: `wait` prints `auth` at once,
with a line on stderr naming it, for a builder and a conductor alike. Only the user's `/login` clears
it. Once they have run it, tell the agent to resume (`swarm.sh tell`), and a conductor tells the same
to each builder whose `wait` printed `auth`. `wait` does not read the pane. `wait --stall
<slug>` also returns, with exit code 3 and `stalled: working <N> min with no commit, edit, session-log write or PR update`, when the
builder (busy, as above) has shown no sign of life (a worktree commit, an uncommitted edit in the
worktree, a write to its session log, a PR update, a swarm action on its story) for `stall_minutes` since that wait began. `watch` is what the lead waits on: it
exits when a story PR's checks finish, when it conflicts with its base, when its head has had no checks
for 10 minutes, or when an agent's session is waiting, and it names what the agent waits for. A codex
agent, or one with no session recorded, counts as waiting when herdr says it is blocked. Each agent's
wait is reported once, and again only after a poll finds that agent no longer waiting; a poll that
cannot read the agents changes nothing. herdr lists every project's agents, so
`watch`, and `next` when it looks for a running conductor, count only agents in panes this project
opened (recorded in `.swarm/state`); an agent started by hand is not watched.

**The goal.** With `goal = N`, once the builder has taken up its brief, `story` sends it `/goal`
followed by the condition in `.swarm/briefs/<slug>.goal.md`, joined onto one line, once, through
`herdr agent prompt`. The condition names the story by its path, so the line stays under
`GOAL_SEND_MAX`, the length past which Claude Code takes it as pasted text. The builder is mid-turn by then; Claude Code still sets the goal straight
away, and runs one extra short turn after the brief's turn ends. From then on Claude Code's judge
keeps the builder working until the story's **Done when** holds, the builder replies
`IMPOSSIBLE: <why>`, or N more turns have passed. The judge records all three as met, and only its
reason text tells them apart. `story` looks for the goal in the builder's session log and does not
read the pane: it waits up to a minute for a `goal_status` entry with that condition (whitespace
aside), written after the send. If Claude Code refused
the goal (hooks restricted by settings or policy, or a folder it does not trust), or no entry came,
`story` fails, names the story and the reason, and leaves the builder open for the lead to look at.
If the log shows the `/goal` queued as a prompt instead, the failure says it was pasted as text.
It never sends the `/goal` again, because a second one would reset a goal that had set.
It types the `/goal` only once Claude Code reports the session busy. If the session is waiting on a
prompt, where Enter could approve what auto mode flagged, or is not busy within a minute, nothing is
typed and `story` fails. A failure after the brief went in says the brief was delivered, so no one
sends it again.
Once the builder takes up findings from `swarm.sh tell <slug> findings <file>`, `tell` sends it a
fresh `/goal` in the same turn, under the same rules. The goal holds until each finding is fixed, or
declined with a reason in the reply, and the builder has sent the reply its brief asks for, or until N
more turns have passed. `tell` fails and names the story unless the session log shows that goal set
after the tell began, and its message says the findings were delivered. A nudge or resume tell sends
no goal.

**Giving up on a builder.** A conductor gives up on a builder when `wait --stall` returns stalled,
when it is idle with no PR after wait's nudges, or
when review has not converged in the rounds it allows. It runs `swarm.sh close <slug>`, which, on a
code, docs or chore story still `ready`, counts the attempt and clears its worktree, branch and PR,
and starts the story again in a later wave with
`swarm.sh story --strict <slug>`; swarm.sh picks the model, Fable once the story has failed `escalate_after`
builds (2 by default). With `escalate_after = 0` it reports a story that has failed twice to the lead
instead. A story that comes back `kind: lead` with `escalated_from:` is the lead's to decide, never
the user's. With `goal` on, a builder idle short of its reply is not nudged: the conductor reads the
cause from its reply and the last met `goal_status` entry's `reason` in its session log, closes it with
`swarm.sh close <slug> <cause>` (`stalled` for a stall), and on `cleared-on-error` starts nothing more
in the wave and lists the story for the lead. A Fable builder can stop on its usage-credits consent, which `wait` prints as
`waiting: dialog open`. Only for an escalate build, and only once `herdr agent read` shows that
consent, the conductor accepts it with `herdr pane send-keys` in the builder's pane, runs
`swarm.sh dialog <slug> accepted` (or `dismissed`, telling the lead), which logs `dialog <slug>`
with its time, and waits on the builder again. It never closes or tells a builder over a dialog, and
a dialog is not an attempt. Any other dialog, and every permission or tool prompt, it leaves alone.
`/swarm-dev:swarm` does the same for the lead's one-off stories.

**Watching it.** `swarm.sh status` lists the agents that need a look (waiting on a prompt, an empty
pane where a start failed, a session gone or unknown, or `auth`: an idle agent whose login expired,
which only your `/login` clears), what waits on you, and the next step. A Stacked section, shown
only when it has a line, lists each stacked build that has to catch up with a parent. It reads the
parents the child's current build stacked on, and compares them with the child's branch on origin,
so a merge the child has not pushed still shows: `<child>: merge origin/story/<p>` when the parent's
open PR has commits the child lacks, `<child>: merge origin/<base> (<p> merged)` once the parent
merged and the child lacks the base's head (one line for all the merged parents; after a squash
merge, the child takes the base), and `<child>: lost story/<p>` when the parent's PR closed unmerged
(as a dropped parent's has), or its branch is gone while its PR is open or, still on the board, it
has no PR. A gh or git call that fails, or a git that cannot tell, gives a `could not check` line.
Inside herdr, a line ends `(no builder)` when the child has no builder open. After each wait, watch
and new PR, the conductor runs `unblock`, starts what it readies, and runs `status`, acting only on
its own stories: its epic's, or for the backlog conductor those with no epic. It tells each child
with a merge line to merge that ref, re-run the tests and push, first starting a builder in the
child's worktree when the line says `(no builder)`, and reviews the new head, since a review from
before the merge is stale. A merge line stays until the child pushes, so the conductor sends each
one once and skips it until the child's builder replies. It closes a lost ready child whose builder
is open with `paused`, which holds it for the lead. It lists for the lead a lost child that has no
builder or that close did not hold. `next` says
`auth` too when the conductor's login expired. A Claude agent's state comes from its own session in `claude agents --json`, read once per
run: busy is working, idle is idle, waiting is WAITING with what it waits for, and a recorded
session with no entry in the list (`gone`: the session ended) or no state in it (`unknown`, also
when there is no `claude` to ask) needs a look. herdr's word stands only for codex agents, agents
with no session recorded, and retired panes. `swarm.sh dash` shows the
same on one screen, for a person to scan: a summary line, then what needs the user first (PRs to
merge with their checks, `lead` stories, agents waiting on a prompt (with what their session waits for), agents whose session is gone or unknown, agents whose login expired, empty panes, stalled
agents), each active epic with a bar of its finished stories (finished story files are deleted,
so they are counted from history: a deletion counts once per slug, and only when it closed the story,
never a re-scope) and its live agents and open PRs beneath it,
and the recent events with how long ago; idle agents and blocked or later items are counts. One
status vocabulary runs through it (● working, ○ ready, ◐ review, ✓ done, ✗ failing, ⏸ blocked, ! needs you or a
session gone or unknown, ? a herdr state dash does not know).
`--tree` shows the agents by workspace and tab and `--ladder` the model per role; `dash --watch
[seconds]` redraws it in place until `q`, with `t` and `l` toggling the two. Both only read: they never change the board, the state or the logs, and never open
or close a pane, so `dash` asks herdr for the agents even outside a herdr pane.


The builder's brief is the story file plus the standing rules (never merge, no real cloud, the
codex loop through `swarm.sh codex-review <base>`, reply with the PR URL when CI is green), the epic's `check:` command when it has one
(the builder runs it before opening the PR), then the project's own rules from
`.claude/swarm/brief.md`. When those rules include tagged ones (`<!-- lesson: <kind> -->`), the
brief adds a last step: before opening the PR, the builder walks its diff against each one and gives
the PR body a `Rules checked:` section, one line per kind naming
what it checked (file:line) or `n/a: <why>`. With no tagged rule there is no step. `herdr agent read <slug> --source recent-unwrapped` shows what an agent
is doing.

**Review before closing.** A PR that changes only board files (no code) gets one
`swarm.sh codex-review` pass plus the lead's own reading, not repeated passes. A story is reviewed when its latest head has passed
codex and, if it changes code, the `/code-review` skill. As soon as a story's PR is green, the
conductor starts a review agent for it with `swarm.sh review-agent <slug> <PR URL>`. It does not
wait for other PRs or reviews, so PRs that land together are reviewed at once. The command returns
straight away. The agent, `review-<slug>`, is read-only and runs in the story's worktree and tab. It
runs `codex-review` with `SWARM_STORY=<slug>` and, when the PR changes code, `/code-review <PR URL>`.
It judges the PR against the story's touches and **Done when**. A point that only a change to a file
outside the touches can fix is out of scope; a gap in the PR's own code is a finding, even where the
touches do not name it. Its brief carries the project's own rules, as a builder's does, and six checks
the lead used to make by hand, which the fallback reviewer's brief carries too. After them come the
decisions the story and its epic mark `(user, <date>)`. Each is the whole bullet that holds the mark,
from its first line, with its sub-bullets, printed as its own bullet and cut at 1500 bytes on a
character boundary. Together they take at most 2000 bytes; past that, the brief says how many were
left out and which files hold them. A mark inside code, or in the story's own **Done when** (which
the brief already quotes), is not a decision. A PR that contradicts a decision is a finding, even
when the PR is stricter. The fallback reviewer gets the decisions
only when codex-review knows the story (`SWARM_STORY`). It writes to the absolute
path `<project>/.swarm/reviews/<slug>.md` (its working directory is the worktree, outside the
project), and replies with that path. It writes the file in one go once both reviews are done,
after `review-agent` has removed the one from an earlier head. The file starts with `head: <SHA>`,
the PR's head, which `review-agent` reads from `gh` and puts in the brief, then `codex skipped:
<why>` when codex was skipped. Under them go the findings,
each with its reviewer and file:line, then an out-of-scope section for points raised outside the
story.
`review-agent` refuses, starting nothing and leaving the last review's file in place, when the board has a story named
`review-<slug>` (whose builder would hold the same agent name), when the worktree is not at the PR's
head or has uncommitted changes, or when `review-<slug>` is still working or still open with no
findings file (idle while its codex runs, not finished). It moves the last review's file aside
before the new agent's brief goes, puts it back if herdr cannot start the agent, and deletes it once
the agent has started. For a story stacked on
parents, the brief names their branches: their code is in the diff against the base, but the agent
lists it neither as a finding nor as out of scope. The conductor waits on each review in the background
with `swarm.sh wait review-<slug>`. A review agent goes idle while its codex runs in the
background, so for an agent agents.tsv records as role `review`, that wait, like a conductor's,
holds on until the findings file exists, and fails if it times out without one. The conductor
then triages that story's file, and closes the review agent whatever
it found. A file with a `head moved:` line, or with no findings section, is not a pass: the
conductor starts the review again. When the wait returns with no file (a timeout, a prompt, a gone
session, an expired login), it closes the review agent without answering its prompt, and reviews
again in a later round or reads the diff itself. It sends the real findings to the story's builder with `swarm.sh tell <slug> findings
<file>`, and logs each out-of-scope item with `log-finding --declined out-of-scope --reviewer <who>`.
It starts a new review agent on the builder's next head. A round is one review whose findings went
to the builder; a review started again (head moved, no findings section, a review agent that timed
out or crashed) is not one. Review stops after round 3: from round 4 on, only a real bug (wrong
behaviour, data loss, a security hole) sends the PR back, and so does a `rules-unchecked` finding
when the project has tagged rules. Anything
smaller is declined with a reason and logged with `log-finding --declined <reason> --reviewer <who>`:
`nit` for a nit or an edge case, `out-of-scope` or `wrong` where they apply. Before a story merges or goes to review, it
compares the file's `head:` line with the PR's head, and reviews the new head when they differ. `tell`'s kind (`findings`, `nudge`
or `resume`) is required and goes in the audit log. `tell` sends only to an idle session. It
refuses a builder that is still working, waiting on a prompt (it names what the prompt is), or whose
session is gone or unknown. To reach a busy conductor, the lead runs
`swarm.sh tell conduct-<epic> note <file>`. It appends the file under a timestamped header to
`.swarm/inbox/conduct-<epic>.md`, without sending a prompt or reading the conductor's state, and
only for a live conductor of this project. After each `wait` or `watch` returns, the conductor moves the
inbox with `mv` to `conduct-<epic>.reading.md` beside it (so a note added meanwhile starts a new
file), reads that copy, acts on it and deletes it. A copy already there is a read that was cut off,
so the conductor reads and deletes it first. It does all of this once more just before it writes its
report, so a note left after its last wait is still read. Once a new conductor has started,
`conduct` clears both files, so it never acts on notes left for the one before. A `conduct` refused
because the epic's conductor is still running leaves them alone. The conductor closes a builder only after both
reviews pass, so the fixes are made by the agent that wrote the code, with its context. A pass
that finds only nits, edge cases outside the story, or points already declined counts as passing: a
reviewer built to find edge cases never comes back empty, so waiting for an empty pass never ends. Each builder
also proves its tests can fail: it breaks its fix, watches a test fail, and restores the fix.

Every codex review a builder, a conductor or the lead runs goes through `swarm.sh codex-review
<base>`, in the worktree, with `SWARM_PROJECT` set to the project so a worktree of another repo still
reads its config. It runs `codex exec review --base origin/<base>` with no prompt (codex refuses one
beside `--base`) and stdin from `/dev/null`, and stops it after `codex_minutes`. With
`SWARM_STORY=<slug>` it passes a prompt in place of `--base`. The prompt asks codex to review the diff
against `origin/<base>`, uncommitted changes and untracked files included, so a builder's review
before its first commit sees its work. It lists the story's touches with its **Done when** and **From review** items,
and holds out of scope only a point that a change to a file outside the touches alone can fix. If `SWARM_STORY` is not a slug, names no story file,
or names a story with no **Done when** item, codex-review fails before codex starts. An interrupted
codex-review stops codex the same way and exits only once it is gone. While it runs it keeps a marker,
`.swarm/state/codex-review.<pid>` (start time, base, worktree), which the dash reads for its codex
row. It removes its marker when it exits, and on start removes any marker whose process has died. codex stays in the caller's
process group, so a harness that kills that group kills codex too. Every brief says to run it in the
background (Bash `run_in_background`) and wait for it: Claude Code stops a foreground Bash call at 2
minutes by default and 10 at most, before the limit could apply. Whoever runs it waits for it to
exit and acts on what it prints last, since a usage limit printed early may be followed by a
fallback's review. When it ends on codex's usage limit or on `codex skipped: ...`, no one runs it again: a
builder carries on, the conductor or the lead reviews the diff itself, and the PR says `codex
skipped: usage limit` or `codex skipped: timed out`. A review agent says `codex skipped: <why>` in
its reply, and the conductor then reads the diff itself in codex's place. codex-review sends codex's
output, stderr merged into stdout, to the screen and to a log in a temp directory of its own (mode
700, so no other user can make or read it first), removed when it exits. Once codex exits,
it waits a few seconds for the output to finish, and on any way out (the timeout and an interrupt
too) it stops the copy, so a child of codex left holding the output cannot hang the caller. If codex fails and its last lines hold its own limit message (`You’ve hit your usage limit`, with
`ERROR:` or `■` before it; a review that only quotes the words does not count), codex-review logs a
`codex-limit` incident in events.tsv, with `codex-<story>` as its target (not the slug, which is the
builder's own agent name). With `fallback_reviewer` empty it then exits as codex did. With
it set, it starts `fallback-<story>` in the worktree on that model, with codex's prompt. The agent
runs with no Edit, Write or NotebookEdit tool and cannot commit or push. It still has Bash, so
unlike codex's read-only sandbox its brief is what keeps it from changing the worktree. It gets what is left of `codex_minutes`, its start included, so the whole run stays within it, to write its
findings to `.swarm/reviews/fallback/<story>.md`, in a tab of its own (`fallback-<story>`). codex-review prints `reviewed by fallback <model>:
codex usage limit` and then the findings, and closes the agent, findings or not; an interrupt closes
it too. The builder treats the findings as codex's, logs them with `--reviewer fallback`, and the PR
body carries that line instead of `codex skipped`. When the agent cannot start (outside herdr,
start_agent refusing, or its name, cut to 32 characters, held by another story's fallback) or writes
nothing in time, codex-review prints `codex skipped: usage limit (<why>)` and exits as codex did. It
waits for the file, not for the agent to go idle: an agent idle while a subagent or a background
call of its own runs has not finished. With
under two minutes of `codex_minutes` left, no fallback starts: it prints `codex skipped: usage limit
(no time left for a fallback)`. The planning `codex` panes of
`/plan-epic` are not run this way: `wait`'s timeout bounds them, and the lead closes them.


## Logs and outcomes

**The audit log.** Every `swarm.sh` command appends one line to `.swarm/events.tsv`: the time,
the command, its target, the herdr pane that ran it, and how it ended: `ok`, `interrupted`, the first
line of the error that stopped it, or `failed (exit N)` when the error came from a nested step, whose
message a caller may have handled (it still reaches the terminal). Only the read-only commands are
exempt (`READ_ONLY_COMMANDS` in `bin/swarm.sh`: `dash`, `status`, `next`, `config`, `policy`,
`cost`, `outcomes`, `flow`, `review-yield`, `features`, `lessons`, `findings`, the `wait`, `wait-pr` and `watch` that conductors and the lead run all the time, `base`, and
`tidy` without `--yes`), so a new command is logged until someone names it read-only. The one
exception is `wait`, which logs each nudge it sends as `nudge <agent>`. The stall rule skips those
lines, because a nudge is not a sign of life. Something that went wrong is an `incident` line,
its outcome `<kind>: <detail>`, which `flow`'s `incidents` section counts. `wait` writes two kinds:
`wait-timeout` when its wait runs out (not when herdr's wait fails sooner, and not for a
`wait --until-report` hour that it waits again), and `login` when it returns `auth`, once per
expired login: a second wait adds none, and a `tell` (the resume after the `/login`) starts a new
one. A `close` that ends a build with no open or merged PR on `story/<slug>` writes `idle-no-pr`,
unless its cause is `stalled`, `paused`, `cleared-on-error` or `impossible`; the waits on that builder write
none, so one stuck builder is one incident. The stall rule skips incident lines as it skips nudges. A `tell` is logged as `tell:<kind>` with the slug as
its target, or as plain `tell` when the kind is missing or wrong. One that reached the builder counts as a swarm action on the story. The stall rule
skips `tell:nudge`, since it is a nudge too, and any tell that ended other than `ok`, since it never
reached the builder. It also skips `tell:note`: a note the lead leaves a conductor says nothing about
whether the conductor is working. A `close` with a cause is logged the same way, as `close:<cause>`, and one with
no cause as plain `close`. A close with an unknown cause is refused and logged as plain `close`,
and the word that was given never reaches the log. `reconcile` and `unblock` write a line
per item they move. `merge` writes all its own lines, under the story's or epic's slug (the PR URL
with `--board`, or before it knows the item): a refusal is one `merge` line saying why, and nothing
else; a PR that `gh pr merge` ran on but that never reads as merged is one `merge unconfirmed
(<state>)` line; otherwise `merge ok`, then `main-ci` with `ok`, `red <checks>`, `timeout (<what it waited on>)`
or `error <why>`, then reconcile's lines. A `story` that starts an `escalate` build, and the `close` that hands its story to
the lead, each write one more line of their own (§ Model and effort). The plugin's merge guard
(§ Merging) writes an `incident` line, target `-` and outcome `merge-blocked: <form>` or `guard-blocked: <form>`, for each call it blocks.
`reconcile` writes one, target `-` and outcome `pull-failed: <files>`, when changed tracked files stop
its pull (§ Merging), once while the same stop lasts, and one with outcome
`key-dropped: <file> <key>: <yours> -> <theirs>` for each uncommitted `status` or `prs` its pull replaced. The log is local to the machine and append-only,
holds names and paths but never a brief's or a message's contents, and a write that fails never
fails the command. The outcome field is the one place free text gets in: the reason given to a
`reset` or `drop`, the answer given to `dialog`, the PR URLs a `review` names (`ok (<PR URLs>)`),
and the first line of a failed command's error.

`swarm.sh outcomes [--since YYYY-MM-DD]` joins the logs per build. It prints one TSV row for each
builder in `.swarm/agents.tsv` with the story's slug, kind and risk, the model and effort, the cost
and tokens from the session's own log, the tells it took by kind (`tells_findings`, `tells_nudge`, `tells_resume`; a bare `tell` from older logs counts as findings, and a refused tell, which never reached it, is not counted) and its `close` lines in this log (any cause), the findings logged
against its PR, the PR and its state from `gh`, and which attempt at the story it was. Then come
`started` (the first timestamp in the session log, in UTC, or empty with no log), the tokens by type
(`tokens_input`, `tokens_cache_write`, `tokens_cache_read` and `tokens_output`, which add up to
`tokens`), `close_cause` (the cause on the build's last close, empty for a plain `close`), and when
each escalation step was logged: `escalate_at`, `dialog_at` with `dialog` (`accepted` or `dismissed`,
otherwise empty), `escalated_at`, `reset_at` and `drop_at`. The reason given to a reset or drop is
never printed. After those: `epic` (the story's `epic:`), `merged_at` (when the build's PR merged),
`story_merged` (`true` on every row of a story when any of its PRs merged, `false` when `gh` found
none merged, and empty when that is unknown: the story is gone, it names no repo here, or `gh`
failed), `findings_declined`, and `findings_fixed_by` and `findings_declined_by`, which count each by
reviewer as `<reviewer>:<n>` pairs in name order (`unknown` for rows logged before the reviewer
column). Four more columns come from `gh`: `pr_created_at` (UTC), `start_to_pr_min` (minutes from
`started` to `pr_created_at`, empty when the build started after its PR already existed, as a retry
does), `pr_to_merge_min` (minutes from `pr_created_at` to `merged_at`), and `main_merges`, the
commits on the PR whose headline merges the base branch into it (`Merge origin/main into …`,
`Merge branch 'main' into …`, `Merge remote-tracking branch 'origin/main' into …`). Each is empty
when its inputs are. `pr_created_at`, `pr_to_merge_min` and `main_merges` describe the PR, not the
build, so they repeat on every build that shares it: count a retried PR once when you sum or average them. Last
come `subagent_cost_usd`, the estimated cost of the builder's subagents, `subagent_cost_by_model`,
the same cost split by model as `<model>:<usd>` pairs joined by commas (`haiku:1.00,opus:2.00`, with
`other` for a model that has no price), and
`subagent_tokens`, their tokens of every type. A
subagent turn is one with `parent_tool_use_id` or `isSidechain` set in the builder's session log, or any
turn in the `subagents/*.jsonl` logs in the folder named after the session, next to its log. `cost_usd`
and the tokens columns count the builder's own turns only, so `cost_usd` plus `subagent_cost_usd` is
the whole build. The subagent columns are empty when there is no session log. When only the copy
`close` keeps of a deleted log is left, they count the subagent turns inside that log alone: the copy
leaves out the `subagents/` logs beside it. After them come five columns that split the minutes
from `started` to `merged_at` into phases: `building_min`, `ci_min` (a check
on the PR's head was running), `review_wait_min` (from `pr_created_at` to the first `review`
event after it, which hands the PR to the merger, or to the merge), `fixing_min` (from each
`tell:findings` logged between `pr_created_at` and the merge to whichever comes first: the PR's
next commit (a commit that merges the base in does not count), the next check start, `review` or
`tell:findings` event, or the merge) and
`merge_wait_min` (from that first `review` event to the merge). A `review` event, of the story or
of its epic (`swarm.sh review <epic> <PRs>`), counts for the PRs it names in its outcome. One logged
before reviews named their PRs (a bare `ok`) counts for its story's PR when exactly one was open then. Where two phases cover the same
minute, the higher one takes it: fixing, then CI, then review wait, then merge wait; a minute none
covers is building. The five add up to the whole minutes from `started` to `merged_at`, and are
empty when either is missing. The events are those of every build of the story, so a retry's tells
count in the first build's minutes too, and the first build's in the retry's; a tell on an earlier,
abandoned PR is not counted, as it came before this PR was created. `gh` gives only the latest run of
each check on the PR's last head, so other CI counts as whichever phase lies under it. A check cancelled while
queued, which `gh` dates to the year 1, adds no CI. The four after `building_min` cover a PR's time
in review, from `pr_created_at` to the merge, so they add up to `pr_to_merge_min`. Next comes
`rework`: 1 when a later fix reworked the build's merged PR and 0 when none did, as defined under `flow`'s `model_fit` section
(below). Any PR merged in the repo can be the fix, whether or not a build made it: `outcomes` lists
the repo's merged PRs once with `gh`, from the first merge day of the builds it judges to 8 days after
the last (`gh` dates in UTC, and a local 7th day can be the next day in UTC). It judges the PRs merged
from 7 days before `--since` on (`flow`'s `--since`, when `flow` runs it), so a 1 shows as soon as a fix
merges, while a 0 waits until 7 days after the merge. The cell is empty on a PR that never merged, on an
earlier build that shares the PR (so a reworked PR counts once), on a PR merged 7 days ago or less with
no fix yet, and where rework is unknown: a PR merged before that window, every PR when `gh` failed, and
a PR merged before the oldest PR of a `gh` list that came back 1000 long, whose fix the list may have
missed. A line on stderr names each of the last two cases. `outcomes` alone
computes rework; `flow`'s `model_fit` and `reviewers` sections read this column. The last column,
`held_min`, is on a story's first build alone: the minutes it sat ready and unstarted under the
conductor run the build started in, counted from the later of the run's start and the story's ready
time. The conductor is its epic's, or the backlog conductor (`conduct --backlog`) for a story with
no epic. The story became ready at its last `ok` `unblock` event, or commit on the board's default
branch that set its `status: ready` (a story added ready, or readied by hand), before the build. A
commit that set it `status: blocked` after that leaves no ready time. A run starts at an `ok`
`conduct` event and ends at the next one, at an `ok` close of the conductor, or when it wrote its
report, whichever comes first. The report's time is its file's (`.swarm/conduct-<epic>.report.md`)
until the next `conduct` removes the file; that `conduct` logs it first as a `report <epic>` line in
events.tsv, `ok (<UTC time>)`. A build that started after its run ended, or with no run, held 0.
`held_min` is empty when the build has no `started` or the story has no ready time by then, and on a
retry, whose own wait is not counted. A story the lead holds after an escalation (`kind: lead` with
`escalated_from:`) shows the kind it was built as. New columns only ever go on the end, so
`flow`, which reads them by name, and anything that cuts columns by position keep
working. The slug comes
from the session's worktree, because agents.tsv cuts names at 32 characters. Each build gets its own
PR: the last of the story's PRs that its session log names, so a retried story shows the first build's
closed PR beside the retry's merged one. A build whose log names none of them has no PR, and a build
with no log left gets the story's PR only when it has exactly one. A story that merged and
left the board is read from git history. If `gh` fails, the PR columns stay empty. Each finding counts
for one build: the latest build on its PR that started on or before the day it was logged, so a
retry that reuses a PR doesn't count the first build's findings again. It writes nothing.

After the rows and a blank line, `outcomes` lists the finding kinds that keep coming back: every kind
fixed (or escaped) on 3 or more distinct PRs in the last 30 days, today included, most PRs first, as
TSV with the columns `recurring prs_30d check check_merged before_30d since_30d`. A declined finding
does not count, and neither does a row whose date is impossible or in the future. Once a story that
names the kind in its front matter (`checks: <kind>`) has merged, which means it was deleted on the
default branch (`origin/HEAD`, or `HEAD` when there is none) and git still has it, `check` is its
slug and `check_merged` is the day of the commit on that branch that deleted it (the merge commit,
for a merged branch). `before_30d` is how many PRs the kind was fixed on in the 30 days before that
day, and `since_30d` the same for the 30 days from it, so you can see whether the check helped. Until
30 days have passed, `since_30d` reads `<n>/<days>d`, the days it covers so far: `1/3d` three days
after the merge is too soon to judge. With nothing recurring, the block is left out. `flow` and `review-yield` skip these lines.

Each `events.tsv` line counts for one build, so a retried story's tells and closes are split among
its builds. A line whose time does not parse counts for none. An escalation step goes by the order of the log. Each `escalate` opens a cycle for the
story's next escalate build in agents.tsv that has none yet. A later escalate build takes the cycle
instead when its session log started nearer this `escalate` than any other of the story's, and nearer
than that first build. So a build whose brief was never taken up (it logged no `escalate`) cannot take
its retry's cycle, and a build whose log is gone keeps its own. The cycle runs until the
story's next `reset`, `drop` or `escalate`, and every step logged in between belongs to that build.
If a step repeats in one cycle, the last one counts. A tell or close goes to the story's build that started last at or before it. A build whose
session log is gone starts at 00:00 local time on its agents.tsv day, converted to UTC.


`swarm.sh close` keeps the Claude session log of each agent it closes (every agent in a tab it closes), because Claude Code deletes those after
`cleanupPeriodDays` (30 by default) and they hold every tool call and the model of every turn. The log
is copied, gzip'd, to `.swarm/sessions/<date>-<agent>-<session>.jsonl.gz`, once per session; a codex
agent has none to keep. Nothing is redacted, because a list of what to scrub misses whatever it
doesn't list, so the copy holds whatever the session held. The copy is readable by its owner only,
and `.swarm/` is git-ignored: the archive stays on the machine, and is never committed or uploaded.
Flow's `cost` section and `outcomes` read a session's live log while it exists and this copy once
Claude Code has deleted it, matching the copy on its session id, so their tokens, cost and slugs
outlast the 30 days. The stall rule, the goal check and `dash` never read the copy: an archive is
no sign that an agent is alive.

## Flow and features

`swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>]` prints the project's
numbers in sections, one per `bin/lib/flow_<name>.py` in name order, each under a `## <name>` line:
`ci_health`, `cost`, `epic_totals`, `features`, `incidents`, `lead_queue`, `model_fit`, `reviewers`, `throughput` and `time_in_state`. Each section gets the window (`--since` and
`--until`, which must be real dates, and `--epic`), the log paths and the `outcomes` rows, and calls
`gh` itself if it needs to. A new section is a new file, so adding one changes neither `flow` nor
the others. `flow` writes nothing. For one release, the old `cost`, `features` and `review-yield`
commands still run, and each prints which section now holds its numbers.

The `ci_health` section prints one TSV row, `prs heads ci_min_median red_runs_per_pr flakes`, over
the github.com PRs of the `outcomes` rows dated in the window (with `--epic`, that epic's); a PR
elsewhere, such as GitHub Enterprise, is left out. Each PR costs two or more `gh` calls, so without
`--since` the window is the 30 days up to `--until` (or today), and a line above the row says so. For each PR, `gh` gives its commits and its
branch's completed workflow runs, and a run counts when its head is one of those commits. `ci_min_median` is the median, over head SHAs, of the minutes from a head's first run
created to its last run updated. `red_runs_per_pr` is the red runs (a failure, a timeout or a run that could not
start; a cancelled or skipped run is not red) over the PRs. `flakes` counts each red run followed by a green one of the
same workflow and event on the same head, so a workflow red on push and green on pull_request is no
flake. `gh run list` shows only a rerun's last attempt, so the section reads each earlier attempt's
conclusion from `gh api`. A run whose times do not parse adds no minutes. When a `gh` call fails or takes over 10 seconds, it prints `ci health: gh failed` and no numbers.

The `cost` section shows where the tokens went: tokens and estimated cost per role for the agents
started in the window, with a `lead` row for your own sessions (by their first timestamp's local
day). With `--epic` it still counts every agent in the window, and says so.

The `epic_totals` section prints one TSV row per epic and a last `all` row, over the `outcomes` rows
dated in the window. With `--epic` it prints that epic's row alone. Each row sums `cost_usd` and
`start_to_pr_min` over its builds. It counts each PR once, however many builds share it:
`pr_to_merge_min` is summed per PR, `merged_prs` is the merged PRs whose `main_merges` `gh` could
read, `main_merged` is how many of those had main merged in, and `main_merged_share` is that
percentage. An open or abandoned PR is left out of the share, as it was from leaner-faster-swarm's
baseline of 55%, which a line after the table gives to compare against. `cost_usd` says how many
builds have no cost (no session log, or a codex agent), as `cost` does: `4.25 (1 not in the logs)`.
The minutes sums skip empty cells: `outcomes` leaves `start_to_pr_min` empty for a retry that started
after its PR was created and for a build with no PR.

The `incidents` section prints TSV `day kind incidents`: the `incident` lines in events.tsv
(§ Logs and outcomes) counted per local day in the window and per kind, whatever the kind, one row
for each pair with any. An incident's target is an agent name, which can be cut short of its slug,
so `--epic` does not narrow it.

The `model_fit` section sets cost against results. It prints one TSV row per model and effort
crossed with a story class, over the stories whose first build is dated in the window (with
`--epic`, that epic's). A story counts under the model and effort of its first build, so a story
escalated to Fable stays under the model it started on, while its cost, attempts and findings
include every build. The class is the story's `kind`, `risk`, a size bucket from `estimate_lines`
(`<=100`, `<=300`, `>300`, or `none`) and the area most of its `touches` files are in: each file's
top-level folder, such as `bin/` or `src/`, or `root` for a file at the project's root (on a tie,
the first one named). Touches split as the
overlap check splits them, so `bin/lib/build.sh:f, g` names one file, a bare name such as `Makefile`
is a file when the project has one, and a note in parentheses names none. Each story is read from the board or
from git history, so merged stories keep their class. The columns are:

- `stories`, the stories built;
- `cost_per_merged_usd`, the cost of all their builds, subagents included, over the stories that merged, ending `(N not in the logs)` for builds with no cost, as in `epic_totals`;
- `first_attempt_merge_rate`, the share that merged on their only build, out of those whose merge
  `gh` could read, leaving out a story still in flight (no merge, an open PR); `-` when none is left;
- `mean_attempts`, builds per story;
- `findings_per_pr`, findings fixed (declined ones left out) over their PRs;
- `rework`, the stories with a merged PR that a later PR fixed within 7 days;
- `escaped`, the escaped findings on their PRs;
- `start_to_merge_min`, the mean minutes from the first build's start to the merge.

A PR is rework when a PR merged after it, on its merge day or up to 7 days later, says it fixes it,
or when a `log-finding --reviewer escaped` row dated up to 7 days after its merge day points at it.
Both count calendar days from the merge day in local time, as `findings.tsv` dates its rows. Saying so
means a fix verb (`fix`, `fixes`, `fixed`, `fixing`, `hotfix`, `bugfix` or `quickfix`), `rework of`
or `regression from` in the title or body, then the PR within 40 characters in the same clause
(clauses end at a sentence end, a `;` or a line break): its URL, `owner/repo#N`, or `#N` from the
same repo. A clause with `merge after`, `depends on`, `stacked on` or `merged origin/main` names a
PR without fixing it. Each reference is judged by the nearest fix verb before it, and a negation
directly before that verb (`doesn't fix`, `not fixing`, `never fixed`) cancels it, so "Fixes #1 and
doesn't fix #4" fixes #1 alone. A negation anywhere else, as in "Fixes #1, which was not a
regression", leaves the fix standing. A release PR (one that changes only `.claude-plugin/plugin.json`)
fixes nothing. The section reads `outcomes`' `rework` column, so a story merged 7 days ago or less
counts as rework only once its fix has merged. `outcomes` lists the merged PRs with `gh`, the last 1000 per repo. A line on stderr
says when a list comes back that long, leaving rework unknown for the PRs merged before its oldest.
When `gh` fails or a list is that long, unknown rework counts as none, and a line under the table says
so, as under `reviewers`. A `mergedAt` that does not parse leaves its PR
out, counted in one line on stderr. A cell with fewer than 5 stories prints its count and `-` in the other columns,
as too few to judge. After a blank line, a `subagents` block gives a row per model and effort of
the builds whose subagents cost more than zero (`outcomes` writes `0.00` for a build that ran
none): what their subagents cost, the build cost (theirs plus the
builder's own), and the subagents' share of it.

The `throughput` section prints one TSV
row per epic and a last `all` row for the project, over the `outcomes` rows dated in the window and
the `events.tsv` lines whose local day is in it. With `--epic` it prints that epic's row alone. `builders_mean` and `builders_max` say how many builds ran at once,
weighted by time, from the first build's start to the last one's end. A build runs from its
`outcomes` `started` until its first `close` after that which no earlier build of the story took,
and before the story's next build with a known start, or else its session log's last entry, and never past local midnight at the end of
the `--until` day. A build with no `started` starts at 00:00 local time on its agents.tsv day, or
when the story's last build with a known end ended, if that is later. A build whose start can't be read is left
out.
`stories` counts the slugs built, `longest_chain` is the longest `depends_on` chain among them (each
story is read from the board or from git history, so merged stories count), and
`stories_per_chain` divides the two. `review_wait_min` is the mean time in minutes from a PR's
`createdAt` (from `gh`) to the first `review-agent` event for its slug. A PR with no such event goes
into `proxy_review_wait_min` instead, timed to its first `tell:findings` or `review` event. Those events
come when a review ends, so the two columns are never averaged together. `stacked`
counts the `stacked` events for the epic's slugs, or all of them on the `all` row. The project
row comes last, so an epic named `all` still gets its own row above it.

The `time_in_state` section prints TSV `epic prs hours largest_first`, one row per epic and a last
`all` row. With `--epic` it prints that epic's row alone. The five phases are summed over the
`outcomes` rows dated in the window that have the phase columns (their PR merged). Each PR counts
once, by its build that started first, since a retried PR repeats its phases on every build, and is
in the window only when that build's date is. `held` is over the same PRs: the `held_min` of each of
their stories, once. `hours` is all six together, and `largest_first` gives each as
`<state>:<hours>h/<share>%`, the largest first, where the share is of `hours`. So
`held:3h/64% review_wait:0.6h/12% fixing:0.4h/9% ci:0.2h/5% merge_wait:0.2h/5% building:0.2h/4%`
says the epic's stories spent most of their time waiting to start.

The `features` section asks whether each feature is worth keeping. It reads the project's own
`docs/features.tsv`, or the file `SWARM_FEATURES` names. With neither, it prints one line saying
there is no feature list, so a project never sees swarm-dev's own features judged against its logs.
The file lists every feature with when it landed (a date, a `#PR` or an epic), the metric it
should move (as a `flow` section or `outcomes` reports it), that metric's baseline
from before it landed (a value naming the command and window it came from, or `unavailable: <why>`),
and its uses. A use is an `ok` `event:<command>` line in events.tsv, by its local day (a `tell` also matches
`tell:findings`), a `role:<role>` or `agent:<name>` line in agents.tsv, or a `reviewer:<who>` row in
findings.tsv. A read-only command leaves no events line, so its uses say `unlogged: <why>`. The
report prints each feature's uses in the window, its metric and its
baseline, and marks `delete?` a feature with no metric, or one whose logged uses have none in the
last 30 days. A feature still settling in is never marked `delete?` for having no uses: one that
landed in the last 30 days, or whose `landed` names an epic still on the board. Both are read in the
repo that holds the features file, since its PRs and epics are there and not in the project being
reported on. A `#PR` landed on the day of the oldest commit whose subject ends `(#N)`. An epic is on
the board while `<board_dir>/epics/<name>.md` exists there, and landed on the day git log shows that
file deleted. The installed plugin carries its board but is not a git checkout, so
`docs/features.tsv` itself gives dates. An epic with neither is judged by its uses, and so is a
`landed` that can't be read, with a warning on stderr. An unlogged feature is judged on its metric alone.
Without `--since`, the window is the 30 days up to `--until` (or up to today). The section ignores
`--epic`.

The `reviewers` section shows what review yields, so the
reviewers can be tuned. The first block is TSV `reviewer kind raised fixed declined decline_rate rework`,
counted from `findings.tsv` rows dated in the window. Each reviewer gets an `all` row and then
a row per kind, most declined first. Rows from before the reviewer column count as `unknown`. Then
come an `all <kind>` row per kind across reviewers and a last `all all` row. The decline rate is
declined over raised as a whole percent. `rework` counts the PRs that line raised a finding on in the window and that
`outcomes` shows as reworked. When `gh` failed for `outcomes`, a last line says rework is unknown. After a blank line, the second block is TSV `prs rounds
rounds_per_pr max_rounds`: the `tells_findings` of every `outcomes` row that has a PR and is dated in
the window, summed per PR, so a PR built twice counts the rounds of both builds and a retry
with its own PR keeps its own. A tell names no reviewer, so rounds are not split by one. With no
`agents.tsv` the second block is all zero. So the window keeps the findings dated in it and the
rounds of builds started in it. `--epic` keeps only the PRs whose builds carry that `epic`
in `outcomes`, in both blocks, and lists in a third block every PR that either block counted, so you
can check what was covered.

## The outer loop

Each finding that review fixed is logged with
`swarm.sh log-finding --reviewer <who> <kind> <PR> "<one line>"`, where the kind names the class of mistake
(`vacuous-test`, `denylist`) and `<who>` is the reviewer that raised it: `codex`, `fallback` (the agent codex-review starts in codex's place on a usage limit), `code-review`, `ci` (a
PR review bot, a check-run note or a code-scanning alert), `conductor` or `lead`, or `skeptic` and `critic` for a plan review's finding on a board PR. A defect that a later fix finds in merged work is logged against the original PR with `log-finding --reviewer escaped <kind> <original PR>`. Its outcome is `escaped`: it counts toward lessons, but `outcomes` and flow's `reviewers` leave it out, since review missed it. Each finding declined is logged with `log-finding --declined <reason> --reviewer <who>`, where the
reason is `out-of-scope` (outside the story's touches and **Done when**), `nit` or `wrong`, and the row keeps it as a seventh field; `lessons` counts the fixed and escaped ones, never the declined, and `outcomes` counts fixed and declined apart. `swarm.sh lessons` counts kinds across PRs: a kind fixed in three or
more PRs that the project's `lessons_file` (default `.claude/swarm/brief.md`) has no rule for is a `candidate`. So is a lead
memory (Claude Code's per-project memory, which builders in their own worktrees never see) whose
frontmatter carries `lesson: <kind>`: tag a memory that is about how code is written, and it reaches
the builders the same way. Every builder and conductor gets that file's rules (the brief is pasted
into their prompts whole; from another `lessons_file`, its tagged rule lines are), so one rule
there reaches every later builder and conductor, in any repo. A rule pasted into a prompt does not
stop the mistake by itself, so each builder checks its diff against every tagged rule and lists what
it checked under `Rules checked:`; the conductor logs a missing section, a missing kind, or a line
that names nothing as a finding of kind `rules-unchecked`. `/swarm-dev:swarm` turns candidates into a short rule, tagged `<!-- lesson: <kind> -->`, and
opens it as a PR titled `lesson: <kind>` for you; it never edits the brief silently, and a kind
whose rule PR you closed is not proposed again. Only PRs from the last 90 days count. A brief over 4 KB (counting `lessons_file`'s tagged lines, which every brief also carries) is flagged, and pruning it is your call: a rule that works stops
its own findings, so quiet is no sign a rule is unneeded. The log is `.swarm/findings.tsv`, local to
the machine: date, kind, PR, the line, its outcome (`fixed`, `declined` or `escaped`; rows written before the
outcome column count as fixed) and the reviewer (`unknown` when a row was logged without `--reviewer`
or before that column existed). Columns added later go on the end, so readers ignore any past the sixth.

**Green means more than green checks.** A check can pass and still carry a failure note (a
code scanner often does), so the lead also triages `swarm.sh findings <repo> <pr>`: the notes on
every check run of the PR's head, and its open code-scanning alerts (the first 100 of each). Each is fixed, or rebutted in
the PR with a reason; none is silenced or dismissed. findings also reads the PR's diff and body. A
test the diff adds (Go `func TestX`, Python `def test_x`, a `check` line in `tests/*_test.sh`, a JS
`it(` or `test(`) needs a line in the body with FAIL and its name, which the builder pastes from the
mutation run. findings prints each test without one as `rules-unchecked`, with the command that
logs it, `log-finding --reviewer ci`.

## Merging

With `merge = human` (the default) no agent merges: each agent starts unable to run
`gh pr merge`, its brief forbids every other route, and the plugin's merge guard (below) refuses the common ones. When a PR is green and reviewed, the lead
runs `swarm.sh review <slug> <PR URL>...`, which sets the item `status: review` with its PRs on a
`prs:` line, and `next` lists it as awaiting your merge. When the stories left in an epic are all
in review and its **Done when** will hold once they merge, the conductor puts the epic in review
too, with every PR still waiting. A `kind: lead` story whose `after:` names its own epic does not count in it
(alone or in a list; an `after:` that does not name its own epic is ignored), so an epic with only
such stories is still planned.
An active epic that had code stories planned (on the board, in its git history, or a board not in
git, which has none to read), none of them open, counts as done in `next`,
`status` and `dash` while its `after:` stories wait, so an epic or story that `depends_on` it goes
ahead. On a board in the story's repo, its last code story's PR deletes the epic file without them.
The `after:` story stays on the board and is listed with the lead's stories. You merge on GitHub; the next `/swarm-dev:swarm` runs `swarm.sh reconcile`,
which finishes each item whose PRs have all merged and sends back to `ready` any item with a PR
closed unmerged; that item keeps its `attempts:`, and reconcile never counts one. While the story
file still names its repo, it also clears each story's build away: its worktree, and `story/<slug>`
here and on origin. A merged story's build always goes; if its builder is still open, reconcile
closes it first, which counts nothing while the story is in review. After a PR closed unmerged, the
build goes only when no builder is open, and the story can then be built again. An open builder may
be fixing that PR, so reconcile keeps its build and prints `build kept: <slug>`. It does the same when
herdr cannot list its agents, since a builder may then be open unseen. After a merge it clears the
build even then, and prints `build cleared: <slug>`: close that builder's pane yourself with
`swarm.sh close <slug>`. Outside herdr it treats every builder as closed and never calls herdr.
Then it pulls the board's repo, fast-forward only. swarm.sh keeps its own keys out of tracked files
(§ Building, Board state), so a main checkout with no edits pulls as it is. With nothing to pull (the
main checkout already has every upstream commit), reconcile goes on and leaves every edit as it is.
reconcile touches nothing, and stops naming why, when the main checkout cannot fast-forward (it has
local commits), or when a tracked file the incoming commits change is changed there too, staged or
not. A changed file the pull leaves alone, such as Obsidian's own settings, stays as it is. A story
or epic the pull changes whose only uncommitted change is to swarm.sh's keys, as an older swarm.sh
wrote them, does not stop it: reconcile moves the values, as the item reads them, into its state and
checks the file out, so the item reads as it did. It stops instead, naming the file, when the incoming
commits change that file's `depends_on` or the same keys, since the old values would read over the new
ones (a status flipped to `ready` over a new dependency): check the file out, and once the pull is in,
set its keys again through swarm.sh. The same value on both sides goes through. A `status` and `prs`
the incoming commits change are the exception: the old ones give way and are dropped, so a story
whose merged PR set `status: done` reads as done. reconcile names each uncommitted value it dropped
that way, with the one that replaced it, so you can set it again if you meant it; an older
swarm.sh's `review`, `building` or held status that an incoming `status: done` finishes is not named.
An untracked board file whose bytes match the incoming file's is removed, and the pull brings it back. A pull git refuses (an untracked file it
would overwrite) also stops reconcile, and reconcile puts back each of those changes first, so a
failed pull changes nothing. On a stop for changed files, it names each of them and logs an
`incident` line in events.tsv with the outcome `pull-failed: <files>`, once while the same stop
lasts. For a board
file it says to land the edit through `swarm.sh board-pr` or check the file out to drop it; for any
other file, to commit or move the change. Then run `swarm.sh reconcile` again. On a board in the
repo, reconcile never deletes a tracked file in the main checkout. An item whose PR merged but left
its file on the board is marked `done` in its state after a pull, or at once when the checkout's
branch has no upstream (there is nothing to pull), and stays on the board until
`swarm.sh finish <slug>` takes it off through a board PR. When reconcile holds the pull because it
cannot read a PR in review, the item stays in review until a later reconcile pulls. On a board outside the repo it deletes the file of the item that merged. `swarm.sh unblock` then readies a
blocked story once every slug in its `depends_on` is finished. It leaves an old `blocked_by` line as it is, since nothing reads it. With `merge = agent` the conductor merges instead, only through `swarm.sh merge`, except for a story with `costs: money`: `swarm.sh merge` holds a PR whose story, or a story it stacks on, has `costs: money` or any other value but `none` for you, on every route (`held: <slug> costs money`). A `costs:` of `none` or empty merges, and an unreadable board story holds every PR (it fails closed). The conductor reviews a held PR, closes its builder and leaves it for your merge. Only the conductor merges. Every agent, the conductor included, still starts unable to run `gh pr merge`. The head a review passed is the `head:` line of the
story's findings file; once the review passes, the conductor reads the PR's head again, and if it is
not that SHA, it reviews the new head. Then it runs `swarm.sh review <slug>
<PR URL>`, then `swarm.sh merge --head <that SHA> <PR URL>`, which merges by the literal PR number
with `--match-head-commit`, never `--auto`, waits for CI on the base, and runs `swarm.sh reconcile`.
That pulls the board the way it does for you, and finishes
the story, closing its builder. The conductor never closes the builder before that, because closing
a story that is still `ready` counts a failed build. It runs one `swarm.sh merge` at a time, and starts
the next only once the last has exited. After each, it runs `swarm.sh unblock` and, in the same
run, starts each story of the epic that unblock printed as `ready:` and that clashes with no
running one (§ Building, Pick the wave). A build cleared on error or given up on stops that: it starts nothing more in
the wave. It reports once no story of the epic that it may start is ready and none is running. If
CI on the base goes red or times out, it merges nothing more and stops: it finds the pair of PRs
that broke it, each green alone, opens the fix or lists it for you, and says so in its report. It stops only when what is left needs the lead: a story only
the lead can finish, or a merge that `swarm.sh merge` refused or could not confirm. The lead merges
with `swarm.sh merge`: a one-off story with `merge = agent`, and any PR you ask it to merge, under
`merge = human` too.

`swarm.sh merge [--board|--release] [--head <sha>] <PR URL>` merges one PR. It refuses, merging nothing,
unless the PR is open, its head is `<sha>` when `--head` names one, and a story or epic in `review`
lists the URL on its `prs:` line. With `--board`, for a board-only PR, the PR must be in the
board's own repo (its origin) and every path it changes, a renamed file's old path too, must be
under the board instead. With `--release`, for a release PR, the PR must be in the project's own
repo and go into its base, and it may change only `"version"` in `.claude-plugin/plugin.json`, since
hooks, MCP servers and command paths there run code. The new version must be MAJOR.MINOR.PATCH and
greater than the base's. No story or epic need list it.
The head must be green: at least one check run, every run
completed as success, skipped or neutral, and every commit status a success. It reads every page,
and any gh error or answer it cannot read is a refusal. It merges with the repo's method (squash
when allowed, else a merge commit, else rebase) and `--match-head-commit`, so a head that moved
after the check stops the merge. It never passes `--auto`. It passes `--admin` only with `merge_admin = on`, and only after `ci_gate admin` passes (§ Settings).

It reads the PR back after `gh pr merge`, whether gh succeeded or not, since an error can follow a
merge GitHub made. A PR that does not read as merged is read again a few times, then logged as
unconfirmed, for you to check by hand: it may well have merged. Only a failed `gh pr merge` on a PR
that still reads open or closed is a refusal. Then it waits up to 30 minutes for CI on the merge
commit, so run it in the background: each workflow whose `on: push` filters cover the base and the
files the PR changes must have a run on that commit, and every run and check there must pass. The
commit needs no check run of its own when no workflow is expected on it, but then it waits a minute
before calling main green, for checks other apps post just after the push. A failed read is a
missed poll, and three in a row end the wait as an error. Without
`--board` or `--release` it then runs `swarm.sh reconcile`, also after a red main, since the PR has merged. It
exits non-zero, naming the check, when main is red or the wait runs out. Inside herdr it runs only
from a pane this project did not start (the lead's), or from a conductor's with `merge = agent`; a
pane it cannot identify is refused.

The plugin also ships a merge guard, a PreToolUse hook on Bash (`hooks/hooks.json`, running
`hooks/merge-guard.sh`), for every Claude session it is installed in, yours included. Inside a swarm
project (a `.claude/swarm/` folder at or above the session's folder, or above its main checkout when
the session is in a git worktree) it refuses a call that does one of four things: runs gh's merge
subcommand, `gh pr merge`, however its words are quoted; makes the REST or GraphQL merge call, `gh api`
on `pulls/<n>/merge` or a `mergePullRequest` or `enablePullRequestAutoMerge` mutation; holds either
of those in text handed to a shell or an interpreter (`bash -c`, `eval`, `python3 -c`, `node -e`, or a
heredoc, here-string or pipe into one, with a code flag or without) or written to a file; or chains
`swarm.sh merge` to another command with `;`, `&`, `&&`, `||`, `|`, a newline, `$( )` or backticks.
It guards against careless commands, not deliberate evasion: a merge reached any other way, such as
through a variable, a script run by `source` or process substitution, `awk`'s `system()` or an
alias, passes. A command that only mentions a merge passes too: `echo`, `printf` and `grep`, a commit message, and a PR
body given as `--body "$(cat <<'EOF' ... EOF)"`. On a refused call the hook exits 2, the session
sees its reason, and `.swarm/events.tsv` gets an incident line. The guard reads only the command, never
the session's folder or the call's description. Once the command says merge the guard fails closed: if
it cannot run its check (no `python3`, input it cannot read, an error of its own), it refuses the
call. Outside a swarm project the guard allows everything else.

The hook also refuses commands that can lose work. In every session in a swarm project, yours
included, it refuses a `cd <dir>` followed by `;` outside a `$( )`: when the `cd` fails, the rest
runs in the folder the session was in, so write `cd <dir> || exit 1 &&`. It refuses a `git checkout`
that would overwrite uncommitted changes: unstaged ones, and staged ones too when it checks out from
a commit (`git checkout HEAD -- f`). Back the file up with `cp` and restore from the copy instead.
swarm.sh starts every Claude agent with `SWARM_AGENT` set to its name. In an agent's session the hook
also refuses `git checkout`, `switch`, `restore`, `reset --hard`, `stash` and `clean` in the
project's main checkout, whether the command runs there from the session's folder, after a `cd`, or
through `git -C`. `git stash list`, `git stash show` and `git clean -n` change nothing, so they pass.
It also refuses an agent's `pkill`, `killall`, `kill $(pgrep ...)` or `kill $(pidof ...)`, and a
`kill` of PID `0` or a negative PID (`kill -9 -1` signals every process you own): any of them can kill
another session's process. `kill $!` and `kill <pid>` pass.
Your own session has no `SWARM_AGENT`, so only the `cd` and `git checkout` rules apply to it. These
rules fail open: an error in them never refuses a call, even one whose command also says merge, and
a command that says `git` or `cd` but not merge passes when the check cannot run at all.

**Merge one at a time.** After each merge, merge the base branch into every other open wave branch before
trusting its CI; a branch that conflicts gets no CI at all, which looks like a hang.

**Keep with the lead:** real-cloud runs, credentials, and anything that changes permissions.

**Clean up.** After each merge, `swarm.sh reconcile` closes the story's builder if it is open and
removes its worktree and `story/<slug>`, here and on origin (§ Merging). By hand,
`swarm.sh close <slug>` closes a story's pane (its tab, when it was the last pane there), and
`swarm.sh close conduct-<epic>` closes the epic's tabs.

## Releases

No story PR bumps `.claude-plugin/plugin.json`. Once main has changes since the last
release, `swarm.sh next` prints `release`: the project has `.claude-plugin/plugin.json`, the tag
`v<version>` for its version is on `origin/<base>`, and a commit since that tag changes a file
outside the board. It reads local refs only, since reconcile has just pulled. The lead opens a PR
from `release/v<new>` that bumps only that file, to the next minor version (a patch when every
change since the tag is a fix), and lists the PRs merged since the tag. With `merge = agent` the
lead merges it with `swarm.sh merge --release` and checks that the tag and the GitHub release
exist. With `merge = human` it waits on your merge.

## Commands

| Command | What it does |
|---|---|
| `/epic <title>` | Write a draft epic with a co-author agent; it is planned once you agree it. |
| `/swarm-dev:swarm` | Run everything after the design, stopping when a decision is yours. |
| `swarm.sh status` | Show agents that need a look, stacked builds whose parent moved or merged, what waits on you, and what runs next. |
| `swarm.sh dash --watch` | Open the live dashboard: a running-now box, how long each working agent has gone without a sign of life, how long each running codex review has run, and a merges-per-day speedometer with two warning lights. `swarm.sh dash --project <dir>` (repeatable) draws several projects. With `lead = session` in the config, only your own steps say needs you; the rest goes in a lead's queue ([details](dash.md)). |
| `swarm.sh conduct <epic>` | Start a fresh conductor for one epic. `swarm.sh conduct --backlog` starts one for the ready stories that have no epic. `watch --backlog` follows their PRs. |
| `swarm.sh wait --until-report conduct-<epic>` | Wait, with no timeout, until an epic's conductor writes its report, waits on a prompt, exits or needs a login. `/swarm-dev:swarm` runs it for you. |
| `swarm.sh wait --lead` | Wait until the lead's queue gains a held or escalated story, or a green PR in review that waits on you, and print each new one. |
| `swarm.sh wait-pr [--timeout <seconds>] <PR URL>` | Wait for the checks on a PR's head and print the head SHA and each check. It exits 0 when all are green and 1 on red. It exits 2 when gh fails (a dropped connection, timeout or rate limit is retried first, up to 3 times in a row), when no check run appears within 5 minutes of the first read that found none (`SWARM_WAIT_PR_GRACE`), and when it is still waiting after `--timeout` seconds (30 minutes by default, `SWARM_MERGE_CI_SECONDS`), naming it; a read that hangs ends there too. Exit 1 always means a red check: any other failure, a bad config line included, exits 2. It polls every 20 seconds (`SWARM_MERGE_POLL`), so run it in the background. |
| `swarm.sh review-agent <slug> <PR URL>` | Start a read-only review agent for one story's PR, scoped to its `touches` and **Done when**. It writes `.swarm/reviews/<slug>.md` and returns at once; conductors run it for each green PR. |
| `swarm.sh story [--strict] <slug>` | Build one story. It warns when an open story of another epic touches the same function or file; `--strict` refuses instead, and conductors always pass it ([details](method.md)). |
| `swarm.sh merge <PR URL>` | Merge a green PR whose story is in review, pinned to the head that passed, then wait for CI on the base branch and take the story off the board. The lead runs it when you ask it to merge. `swarm.sh merge --release <PR URL>` merges the lead's version-bump PR, which changes only `.claude-plugin/plugin.json`. |
| `swarm.sh board-pr start\|open\|done <name>` | Make a board edit in its own worktree (`<repo>-wt/_board-<name>`) and open it as a PR. It refuses a change outside the board, and never touches the main checkout. The lead runs it for each board edit. |
| `swarm.sh finish <slug>`, `swarm.sh drop <slug> <reason>` | Take a merged story or epic (or, with `drop`, an escalated story) off the board. On a board in the repo it deletes the file in the board PR `finish-<slug>` (or `drop-<slug>`), never in the main checkout, and prints the `swarm.sh merge --board <url>` that lands it. On a board outside the repo it deletes the file where it is. |
| `swarm.sh log-finding [--declined <reason> \| --filed] [--reviewer <who>] <kind> <PR URL> <text>` | Log a review finding by kind. `--declined <reason>` records one that was declined (`out-of-scope`, `nit` or `wrong`). `--filed` records that the lead filed a declined out-of-scope finding as a story, so `swarm.sh next` stops offering it; no report counts a filed row. The reviewer is codex, fallback, code-review, ci, conductor, lead, skeptic, critic, or escaped for a defect found after its PR merged. |
| `swarm.sh lessons [--all]` | List kinds of finding that recur in three or more PRs and have no rule yet. |
| `swarm.sh outcomes` | One row per build: model, cost and tokens by type, review rounds and other tells, its epic, whether its PR and its story merged and when, findings fixed and declined by reviewer, when it started, why it was last closed, its escalation steps, and minutes from start to PR and from PR to merge. |
| `swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>]` | The project's numbers, a section each: `ci_health` (median CI minutes per PR head, red runs per PR and flakes), `cost` (where the tokens went, with a row for the lead's own sessions), `epic_totals` (each epic's cost, start-to-PR and PR-to-merge minutes, and the share of its PRs that needed main merged in, beside the 55% baseline), `features` (each feature in `docs/features.tsv` against its metric and baseline, with the ones nobody uses or measures flagged for deletion), `incidents` (incident lines per day and kind), `lead_queue` (per day, the median and longest wait on the lead, and what still waits), `model_fit` (cost against results per model and story class, and builder subagents' share of build cost), `reviewers` (findings each reviewer raised per kind, fixed or declined, and review rounds per PR; `--epic` counts only that epic's PRs and lists them), `throughput` (builders at once, stories per chain, review wait and stacked starts, per epic) and `time_in_state` (hours per epic in each state: held ready before a build, building, CI, review wait, fixing and merge wait, with each one's share, largest first). |

## Cleanup, escalation and session logs

Every agent is a full Claude Code session, on a model chosen by its role, and planning one epic
starts about ten agents. Agents use your own `claude`, `codex`, `gh` and `git` logins and never
touch real cloud or credentials. By default no agent merges; with `merge = agent` only the conductor
does.

When `swarm.sh close` closes the builder of a code, docs or chore story that is still `ready`, it
counts a failed build in the story's `attempts:` and clears the attempt away: its worktree, its
`story/<slug>` branch here and on origin, and any open PR, closed unmerged. `swarm.sh reconcile`
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

`swarm.sh close` keeps a copy of each closed agent's session log in `.swarm/sessions/`, because
Claude Code deletes them after 30 days. The copy is not redacted, so it can hold secrets the session
saw. Only your user can read it, and `.swarm/` is git-ignored, so it never leaves your machine.
Flow's `cost` section and `outcomes` read the copy once the original is gone.

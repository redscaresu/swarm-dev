# The method

Work is planned top-down, the user approves each level before the next is made, and every agent
at every level runs in its own herdr pane so it can be watched.

## The planning chain

1. **HLD**: `/hld <title>` opens a pane on the most capable model, where the user writes
   `docs/hld/YYYY-MM-DD-<slug>.md` with it. A reviewer attacks the draft before it is `agreed`
   (§ Writing the HLD).
2. **Epics**: `/plan-hld <hld>` runs a swarm that splits the HLD into epics, each with a
   **Done when** that could fail. Skeptics and codex check for gaps and overlaps.
3. **Stories**: `/plan-epic <epic>` runs a swarm that splits each epic into one-PR stories.
4. **Build**: `swarm.sh conduct <epic>` hands the epic to a fresh conductor, which builds its
   `ready` stories in parallel panes and merges them.

`/swarm` runs the chain after the HLD: `swarm.sh next` reads the board and names the next step,
`/swarm` does it and loops, stopping only at an approval, a draft HLD, a `lead`
story, or a `later` epic. The board is the only state, so a run can stop anywhere and the next
`/swarm` continues. Building comes first (a conductor still working, then an active epic's ready
stories, then one-offs), then planning (an active epic with no stories, then an agreed HLD with
no epics).

A story the swarm must not build says so with `kind: lead`: the lead runs it, and any step that is
the user's is marked **You:** in it (§ Who does what). An open question for the user is a `lead`
story too, so the board's **Waiting on you** view lists it. An epic is done
when its last story's PR deletes the epic file and marks it done in the HLD's `## Epics`.

The session that runs the chain supervises, reviews and merges; it does not do the agents' work.

## Who does what

Three parties do the work, and which one does each step is decided when the work is planned,
not found out while building.

- **You** agree the HLD, approve the epics and the stories, merge PRs (with `merge = human`), say go
  before each `lead` story, and do its **You:** steps.
- **The lead** is your own Claude Code session, the one you run `/swarm` in. It supervises,
  reviews, and runs `lead` stories while you watch: they touch real cloud or credentials, are hard
  to undo, or need a step from you, so they need your logins, your go-ahead or your hand.
- **Agents** plan, conduct and build everything else, each in its own pane; builders also get
  their own worktree.

A story is `kind: lead`, never an agent's, when it:

- changes real cloud, uses credentials, or changes permissions;
- is hard to undo (deletes data, turns something off, a production change): its **Done when** names
  your go-ahead;
- needs a person: a decision, a portal click, another team's approval, a hand PR, a network only
  you can reach. That step is a **You:** line in the story. The lead does the rest around it: it
  prepares the PR or the request, and checks the result after.

A merge is never a story of its own: with `merge = human` every merge is yours already. A `kind`
that is none of code, docs, chore, verify or lead (a typo, or `operator` from older boards) is
never built: `swarm.sh` stops and names it.

**Planned up front.** `/plan-hld` writes each epic's **Your part**: the human steps it expects.
`/plan-epic` turns them into `lead` stories, and its report ends with **What you will do**, so
you see your share of the work before you approve it. A step found during the build that needs
you is a new `lead` story, added to the board, not done quietly.

**Every stop names its exit.** A `lead` story says what it needs from you (a go-ahead, a login, a
network) in its body, and each **You:** step says how the lead learns it is done (you tell it, or
it sees the merge). A status or flag raised for you says who clears it and how.

## Writing the HLD

Everything starts here, and it is the one stage you do by hand: the HLD decides what every epic,
story and line of code after it is for, so it is written with you, not for you.

1. **Start it.** In your Claude session, inside herdr: `/hld <title>`, for example
   `/hld Add rate limiting to the API`. This creates `docs/hld/YYYY-MM-DD-<slug>.md` from the
   template with `status: draft`, and opens a new pane (tab `hld`) with a co-author on the most
   capable model. Your session only supervises from here.
2. **Write it in the co-author's pane.** Switch to that pane and talk to it there. It reads the
   code, the ADRs and `AGENTS.md` first, then asks you the questions that decide the design, one
   or two at a time, and writes your answers into the file section by section, citing evidence.
   It does not invent requirements, commit, or change `status`.
3. **Say it is ready**, to the co-author, in the same pane. A reviewer (the most capable model, at
   `xhigh` effort) starts on its own and attacks the draft: goals that cannot be verified, a
   design that contradicts an ADR or a safety rule, missing alternatives, unnamed risks, open
   questions that would block splitting it into epics. Its findings arrive in the co-author's
   pane; go through them there and revise until you are satisfied. You never switch tabs.
4. **Agree it**, to the co-author. Your session, waiting in the background, sets `status: agreed`,
   opens a PR for the HLD (reviewed like any other change), and closes the co-author's pane. Only
   you can agree an HLD; no agent changes its status.
5. **Hand over.** Run `/swarm`. It sees an agreed HLD with no epics and starts `/plan-hld`.

**What a good HLD has.** The template's sections: Problem (with evidence), Goals, Non-goals,
Current state, Design, Alternatives, Risks and safety, Rollout, Open questions, and Epics (filled
in later by `/plan-hld`). The ones that matter most downstream: **Goals** that could be checked
and fail, because each epic's **Done when** comes from them; **Non-goals**, which keep the
decomposition from growing; **Rollout**, which becomes the order of the epics; and **Open
questions**, which must be answered or explicitly deferred before the HLD is agreed.

**Stopping and resuming.** The HLD is a file, so nothing is lost if you stop: run `/hld` on its own
(or `/swarm`, which sees the draft) and a new co-author picks up the draft in progress from the
file; if there are several, it asks which. With no draft at all, it tells you where the chain
stands instead. To
replace a design later, write a new HLD and set the old one `status: superseded`.

## The board

The board is files: `docs/hld/`, `docs/epics/` and `docs/stories/`, one file per item, with front
matter the scripts read. There is no shared board file to conflict on; the PR that finishes a story
deletes its file (or, with `finished = mark`, sets it `status: done`), and the PR is the record. A project can move the board and change how finished
items leave it (§ Configuring a project). `templates/docs/` holds the READMEs that define
each format and two Obsidian Bases (`Board.base`, `HLDs.base`) that show the board as a view.

## Configuring a project

`swarm.sh init`, run from the project's git root, copies the board templates into `board_dir`
without overwriting a file, creates `.claude/swarm/`, and adds `.swarm/` and the board's Obsidian
lines to `.gitignore`.

`.claude/swarm/config` holds `key = value` lines and `#` comments. The script parses it and never
runs it; an unknown key or a bad value stops `swarm.sh` with the file and line. `swarm.sh config`
prints every setting and where it came from.

| Key | Default | What it does |
|---|---|---|
| `board_dir` | `docs` | where the board is, relative to the project unless absolute |
| `repos_dir` | the project's parent | where a story's `repo: <name>` is found |
| `base_branches` | origin's default branch | branches to try, in order, as the base: `dev main` means `dev` where origin has it, else `main` |
| `finished` | `delete` | `mark` keeps a finished item on the board as `status: done` |
| `merge` | `human` | `human`: no agent merges, and a green, reviewed PR waits for you (§ Merging). `agent`: the conductor merges |
| `review_bot` | `off` | `auto`: the conductor also runs the repo's PR review bot on each PR ([`review.md`](review.md)) |
| `sign_commits` | `false` | `true`: every agent signs its commits and merges, and stops if it cannot |
| `keep_panes` | `false` | `true`: `swarm.sh close` leaves a finished agent's pane and tabs open to read; you close them |
| `lessons_file` | `.claude/swarm/brief.md` | where adopted lesson rules live: the brief, `AGENTS.md`, `CLAUDE.md` or `.claude/CLAUDE.md`, the files every agent reads (any other is refused, since a rule there would retire its candidate without reaching anyone). With `AGENTS.md`, rules about writing code reach you and interactive sessions too, and the brief keeps the swarm-only rules. Every brief still gets the file's tagged rule lines (only those), since a builder in another repo's worktree reads that repo's `AGENTS.md`, not this one. The 4 KB cap measures what every prompt carries: the brief plus `lessons_file`'s tagged rule lines; the rest of `AGENTS.md` is not capped |
| `stall_minutes` | `30` | a story's builder that is working this long with no sign of life (no commit in its worktree, no update to its PR, no swarm action on its story) is `stalled?`: `wait --stall` returns on it, and `dash` marks it `!` and lists it under needs you. Working is its Claude session reporting busy, for `wait --stall` and `dash` alike, and herdr's working for a codex builder |
| `pr_per` | `story` | `epic`: an epic's stories merge into one branch, and each repo gets one PR for the epic (§ One PR per epic) |

The project is `$SWARM_PROJECT` if set, else the nearest directory up from where you are with
`.claude/swarm/config`, else the git repo you are in. A worktree resolves to its main checkout. The
project need not be a git repo: a board kept in a notes vault works, as long as every story names
its `repo:`. When the board is not in the story's repo, the builder leaves the story file alone and
the lead runs `swarm.sh finish <slug>` once the PR merges.

## Model and effort

Every agent's model and effort come from its role, set in one place: `policy()` in
`bin/swarm.sh` (`swarm.sh policy <role>` prints it). Spend on judgment, save on reading:

- **Design is Fable.** The HLD is co-written at `high`, because the user waits on every turn, and
  attacked at `xhigh` before it is agreed. Splitting an HLD into epics shapes all the work below
  it, so it runs on Fable at `xhigh`.
- **Judgment is Opus.** An epic's decomposition into stories runs at `xhigh`. Skeptics and the
  critic run at `high`, because a skeptic is the only gate a story passes before it is built.
- **Reading is Sonnet, running is Haiku.** Surveys read and cite at `high`, since they feed the
  lead, and docs run on Sonnet at `medium`. Verification and chores run on Haiku at `medium`:
  their result is a command's output or a mechanical diff, checked by the conductor.
- **Building code is Opus at `high`**, and at `xhigh` for a story marked `risk: high`.
- **Codex is the cross-model check**, read-only, because a different model family shares fewer
  blind spots with the one that wrote the plan.
- **Below the design level, Fable is escalation only**: a story that failed twice, or an epic whose
  contradictions no one can reconcile.
- **Measure before tuning.** `swarm.sh` records every agent it starts (role, model, effort,
  session) in `.swarm/agents.tsv`, and `swarm.sh cost` turns that and Claude Code's logs into
  tokens and estimated cost per role. Change `policy()` from that table, not from a guess.
- **The conductor is Opus at `high`, one fresh session per epic**, on the standard context window,
  never 1M. A conductor re-reads its whole context every turn: on the project this came from, one
  long-lived lead session was 80% of all tokens over three days (3.6B of 4.5B, at up to 1M
  context). The board carries the state, so a new conductor costs little.

## Scoping an epic

An epic (`docs/epics/<slug>.md`: goal, **Done when**, out of scope, constraints) becomes stories
with `/plan-epic <slug>`: three surveys (where it lands, what constrains it, what overlaps it), one
lead decomposition into one-PR stories with `kind`, `touches` and `depends_on`, a skeptic per story
(capped at five, the rest logged) and a codex pass, then a critic. Agents write their answers to
`.swarm/<epic>/`. The user sees refuted stories and contradictions first and approves before any
story file is written. About ten agents per run, so scope deliberately.

**Ship code switched off.** Code that adds a flag or setting merges with it off, so the merge
changes no behaviour; a separate `lead` story turns it on. Bundled, a failure cannot say whether
the code or the switch broke it, and the rollback has to undo both.

## Building

`swarm.sh conduct <epic>` starts a fresh conductor that drives the epic's stories to merge, then
stops and reports; the session it was started from stays free. Its last act is writing that report
to `.swarm/conduct-<epic>.report.md`, and that file, not the agent going idle, is how `/swarm`
knows it has finished: a conductor is idle whenever it waits on its own background work. It runs in a herdr workspace named
for the epic's HLD (its `hld:` field; every epic of that HLD shares it), in a tab named for the
epic, in a pane named `conductor`. Each story it starts gets a pane in that tab, named for the
story; a tab holds four panes, and the fifth opens `<epic>-2`. A one-off story gets a tab of its
own. Run one conductor at a
time: `watch` reports every story PR, and shared files are the lead's alone.

**Pick the wave.** Only `ready` stories whose `touches` do not overlap. Work that edits a shared
file (`AGENTS.md`, root config, schemas, hygiene scripts) is done by the lead, alone.

```bash
swarm.sh story <slug>      # worktree on story/<slug>, a pane, the agent, its brief
swarm.sh wait <slug>       # in the background: returns when it settles
swarm.sh watch             # in the background: returns when a story PR needs the lead
```

`wait` returns when the agent's Claude session reports `idle`, `waiting` (printed with what it
waits on, such as `waiting: permission prompt`) or `gone` (its session has no entry in `claude agents
--json`, or one with no status: the process exited), which can be early. herdr's `agent wait` is only the wake-up, in
STALL_POLL_MS slices (a minute); after each wake or slice `wait` reads the session once, and never
herdr's word for it. A session Claude Code gives no state for (`unknown`, or the list call failed)
is waited on, said once on stderr. At the timeout `wait` prints the last state and exits 1, and so
it does at once when herdr's wait fails other than by timing out and the session has not settled.
A codex agent, or one with no recorded session, is waited on through herdr's status. A builder
whose session goes idle while its story is `ready` and has no PR (for an epic's story with `pr_per =
epic`, before `story/<slug>` is pushed) has stopped early, perhaps on an API error, and nothing else would wake it. `wait` tells it
why ("you are idle and story/<slug> has no PR") and waits again, up to three times. Nudges are at
least a slice apart unless the session turns busy in between. If herdr cannot deliver a nudge,
`wait` stops there and returns idle, and logs nothing for it. Only code, docs and chore stories are
nudged, never a verify story, a conductor or a planner, and a gh or git call that fails counts as a
PR. An idle agent whose transcript (its session's `.jsonl`, the file `cost` reads) ends on Claude
Code's "Login expired · Please run /login" is never nudged or waited on: `wait` prints `auth` at once,
with a line on stderr naming it, for a builder and a conductor alike. Only the user's `/login` clears
it. Once they have run it, tell the agent to resume (`swarm.sh tell`), and a conductor tells the same
to each builder whose `wait` printed `auth`. `wait` does not read the pane. `wait --stall
<slug>` also returns, with exit code 3 and `stalled: working <N> min with no commit or PR update`, when the
builder (busy, as above) has shown no sign of life (a worktree commit, a PR update, a swarm action
on its story) for `stall_minutes` since that wait began. `watch` is what the lead waits on: it
exits when a story PR's checks finish, when it conflicts with its base, when its head has had no checks
for 10 minutes, or when an agent is blocked on a prompt. herdr lists every project's agents, so
`watch`, and `next` when it looks for a running conductor, count only agents in panes this project
opened (recorded in `.swarm/state`); an agent started by hand is not watched.

**Watching it.** `swarm.sh status` lists the agents that need a look (waiting on a prompt, an
empty pane where a start failed, or a session gone or unknown), what waits on you, and the next
step. A Claude agent's state comes from its own session in `claude agents --json`, read once per
run: busy is working, idle is idle, waiting is WAITING with what it waits for, and a recorded
session with no entry in the list (`gone`: the session ended) or no state in it (`unknown`, also
when there is no `claude` to ask) needs a look. herdr's word stands only for codex agents, agents
with no session recorded, and retired panes. `swarm.sh dash` shows the
same on one screen, for a person to scan: a summary line, then what needs the user first (PRs to
merge with their checks, `lead` stories, agents waiting on a prompt (with what their session waits for), agents whose session is gone or unknown, empty panes, stalled builders,
draft HLDs), each active epic with a bar of its finished stories (finished story files are deleted,
so they are counted from history: a deletion counts once per slug, and only when it closed the story,
never a re-scope) and its live agents and open PRs beneath it,
and the recent events with how long ago; idle agents and blocked or later items are counts. One
status vocabulary runs through it (● working, ○ ready, ◐ review, ✓ done, ✗ failing, ⏸ blocked, ! needs you or a
session gone or unknown, ? a herdr state dash does not know).
`--tree` shows the agents by workspace and tab and `--ladder` the model per role; `dash --watch
[seconds]` redraws it in place until `q`, with `t` and `l` toggling the two. Both only read: they never change the board, the state or the logs, and never open
or close a pane, so `dash` asks herdr for the agents even outside a herdr pane.

**The audit log.** Every `swarm.sh` command appends one line to `.swarm/events.tsv`: the time,
the command, its target, the herdr pane that ran it, and how it ended: `ok`, `interrupted`, the first
line of the error that stopped it, or `failed (exit N)` when the error came from a nested step, whose
message a caller may have handled (it still reaches the terminal). Only the read-only commands are
exempt (`READ_ONLY_COMMANDS` in `bin/swarm.sh`: `dash`, `status`, `next`, `config`, `policy`,
`cost`, `lessons`, `findings`, the `wait` and `watch` that conductors run all the time, `base`, and
`tidy` without `--yes`), so a new command is logged until someone names it read-only. The one
exception is `wait`, which logs each nudge it sends as `nudge <agent>`. The stall rule skips those
lines, because a nudge is not a sign of life. `reconcile` and `unblock` write a line
per item they move. The log is local to the machine and append-only,
holds names and paths but never a brief's or a message's contents, and a write that fails never
fails the command.

The builder's brief is the story file plus the standing rules (never merge, no real cloud, the
codex loop, reply with the PR URL when CI is green), the epic's `check:` command when it has one
(the builder runs it before opening the PR), then the project's own rules from
`.claude/swarm/brief.md`. `herdr agent read <slug> --source recent-unwrapped` shows what an agent
is doing.

**Review before closing.** A story is reviewed when its latest head has passed codex and, if it
changes code, the `/code-review` skill. The conductor sends the findings to the story's builder with
`swarm.sh tell <slug> <file>` and reviews the new head again. It closes a builder only after both
reviews pass, so the fixes are made by the agent that wrote the code, with its context. A pass
that finds only nits, edge cases outside the story, or points already declined counts as passing: a
reviewer built to find edge cases never comes back empty, so waiting for an empty pass never ends. With
`pr_per = epic`, stories have no PR: each epic PR gets `/code-review`, fixed on the epic branch. Each builder
also proves its tests can fail: it breaks its fix, watches a test fail, and restores the fix.

**Learning across epics (the outer loop).** Each finding that review fixed is logged with
`swarm.sh log-finding <kind> <PR> "<one line>"`, where the kind names the class of mistake
(`vacuous-test`, `denylist`). `swarm.sh lessons` counts kinds across PRs: a kind fixed in three or
more PRs that the project's `lessons_file` (default `.claude/swarm/brief.md`) has no rule for is a `candidate`. So is a lead
memory (Claude Code's per-project memory, which builders in their own worktrees never see) whose
frontmatter carries `lesson: <kind>`: tag a memory that is about how code is written, and it reaches
the builders the same way. Every builder and conductor gets that file's rules (the brief is pasted
into their prompts whole; from another `lessons_file`, its tagged rule lines are), so one rule
there reaches every later builder and conductor, in any repo. `/swarm` turns candidates into a short rule, tagged `<!-- lesson: <kind> -->`, and
opens it as a PR titled `lesson: <kind>` for you; it never edits the brief silently, and a kind
whose rule PR you closed is not proposed again. Only PRs from the last 90 days count. With `pr_per = epic` a finding is logged against the epic
PR of its repo, so findings count per epic per repo. A brief over 4 KB (counting `lessons_file`'s tagged lines, which every brief also carries) is flagged, and pruning it is your call: a rule that works stops
its own findings, so quiet is no sign a rule is unneeded. The log is `.swarm/findings.tsv`, local to
the machine.

**Green means more than green checks.** A check can pass and still carry a failure note (a
code scanner often does), so the lead also triages `swarm.sh findings <repo> <pr>`: the notes on
every check run of the PR's head, and its open code-scanning alerts (the first 100 of each). Each is fixed, or rebutted in
the PR with a reason; none is silenced or dismissed.

**Merging.** With `merge = human` (the default) no agent merges: each agent starts unable to run
`gh pr merge`, and its brief forbids every other route. When a PR is green and reviewed, the lead
runs `swarm.sh review <slug> <PR URL>...`, which sets the item `status: review` with its PRs on a
`prs:` line, and `next` lists it as awaiting your merge. When the stories left in an epic are all
in review and its **Done when** will hold once they merge, the conductor puts the epic in review
too, with every PR still waiting. You merge on GitHub; the next `/swarm` runs `swarm.sh reconcile`,
which finishes each item whose PRs have all merged and sends back to `ready` any item with a PR
closed unmerged. Before it pulls the board's repo, it puts back any board file the main checkout
left unstaged with content already the base's, so a hand edit that matches what merged does not
stop it; it first backs each one up in `.swarm/state/reconcile-backup/` and restores them all if
the pull still fails. It touches nothing, and stops naming why, when the pull cannot fast-forward or
a file outside the board is changed; a staged or differing edit is left alone and still stops it. `swarm.sh unblock` then readies a
blocked story once every slug in both its `blocked_by` and its `depends_on` is finished. With `merge = agent` the conductor merges instead:

**Merge one at a time.** After each merge, merge the base branch into every other open wave branch before
trusting its CI; a branch that conflicts gets no CI at all, which looks like a hang.

**One PR per epic.** With `pr_per = epic`, the first story of an epic built in a repo creates
`epic/<epic>` there from the repo's base branch, and adds the repo to the epic's `repos:` line.
Each story branches from `epic/<epic>`, and its builder pushes `story/<slug>` and opens no PR. The
conductor reviews each branch, merges it into `epic/<epic>` with `git merge --no-ff`, runs the tests
and the epic's `check:`, and finishes the story. When the last story is in, it runs codex over the
whole epic against the base (`swarm.sh base <repo>` prints it) and opens one PR per repo, written
for a reader who knows nothing of the stories. Those PRs then go through the same green and merge
rules as any other. If a conductor stops before the PRs, `next` sees an active epic with a
`repos:` line and no open story, and starts a fresh one, which picks up there. Stories outside any
epic keep their own PR.

**Keep with the lead:** real-cloud runs, credentials, and anything that changes permissions.

**Clean up.** After each merge, `git worktree remove ../<repo>-wt/<slug>`, then
`git worktree prune`, and `swarm.sh close <slug>` closes the story's pane (its tab, when it was
the last pane there). `swarm.sh close conduct-<epic>` closes the epic's tabs.

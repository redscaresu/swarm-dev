# Reference: The lead

Part of [the reference](reference.md), which lists every section and the file that holds it.

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
  `open scope-<epic>` also refuses when the worktree leaves `<epic>` at `status: split` (a large
  epic split into child epics, where the base has it at any other status) and `.swarm/<epic>/split-critic.json` holds no `{findings:[...]}`, or
  is older than the worktree (an abandoned draft's): the split critic answers before the board PR
  opens. Once it opens, `.swarm/<epic>/split-pr` records its day and URL for `flow`. A later
  `scope-<epic>` board PR on an epic the base already has split (a missed child, a split-gap fix)
  needs no critic and leaves that record alone.
  `open` also refuses, before it commits or pushes, when an epic goes `active` (new, or at the base
  with any status but `active`: `draft`, `later`, `split`, `review`, `done` or none) with no
  ticket: an `agreed:` date the base's copy did not already have, dated today or up to 7 days
  before it, a `parent:` naming another epic that is `active` or `split` on the base, and in the
  worktree too when the PR changes its file (not a draft, and not one the PR adds or takes out of
  `active` or `split`), or an `hld:`
  naming an HLD that is `agreed` and grants `epics` both at the base and in the worktree. It fetches `origin/<base>`
  first, and a failed fetch or read refuses. `lead_epics = on` skips the check. Commit the epic as `status: draft`, then run `/swarm-dev:epic <slug>`.
  A renamed epic is judged by the base's copy at its old path, when that path was an epic too: an
  `agreed:` date that copy already had is not a ticket, and its `active` carries over only while the
  epic keeps its `# ` heading, so renaming an `active` epic needs no ticket. git pairs a rename by
  content, uncommitted moves included, and pairs a deleted epic with a new one that is half alike
  too, so the heading decides: an epic moved and given another heading needs a ticket, its old
  `agreed:` still counted, and one more than half rewritten reads as new.
  Today is the day the check runs, not the PR's merge base, so `agreed:` must still be within 7
  days when `swarm.sh merge` runs (a board PR's or a story PR's), and a date after today never counts.
  To start a `later` epic on the user's go, write `agreed: <today>` in the edit that sets it `active`, as `/swarm-dev:epic` does.
  `swarm.sh merge` refuses the same change in a board PR (`--board`) or a story PR (§ Merging).
  `open` also refuses an epic set `active` before the base allows its stage (§ Writing an epic,
  Staged epics), whatever `lead_epics` says.
- `done <name>` removes `board/<name>` on origin, then the worktree and the branch here, once the PR
  on the branch's tip (the local one, or origin's when there is none here) has merged or closed. A
  PR left by an earlier use of the name does not count. With no PR it removes an abandoned start:
  a branch with no commits past the base. It runs every check before it removes anything, and
  refuses while any PR on the branch is open, when origin cannot be read or its branch has moved
  past the local one, when the worktree at that path is not on `board/<name>`, has uncommitted
  changes or is locked, when `board/<name>` is checked out anywhere else (the main checkout, or
  another worktree), and when git cannot remove the worktree (giving git's reason). Origin's
  branch goes first, so when its delete fails the local state is still there for the next run.

**Board PR kinds.** `open` names the PR's kind from its name, on stderr; its stdout stays the URL
alone. Only a plan or an agreement PR gets a codex review, and only when its name names an HLD or
epic in the PR's worktree (by the file name lower-cased, each run of characters other than `a-z`
and `0-9` one `-`, trimmed). A story slug that starts the same way, such as `plan-hld-gaps`, is a
story-scope edit:

- plan: `plan-<hld>` (`/plan-hld`) and `scope-<epic>` (`/plan-epic`). It needs one
  `swarm.sh codex-review` pass before it merges, which those commands run before `open`.
- agreement: `agree-<hld or epic>`, the HLD or epic the user agreed (`/hld` and `/epic` step 5).
  One `swarm.sh codex-review` pass before it merges, which those commands run before `open` too.
- finish: `finish-<slug>` and `drop-<slug>`, which `swarm.sh finish` and `swarm.sh drop` open. No
  codex-review.
- hold: `hold-<slug>`. No codex-review. (`swarm.sh hold` itself only logs.)
- story-scope edit: any other name, such as a re-scope, `stage-v<x-y-z>` or `check-<kind>`. No
  codex-review.

The line names no way to land the PR: `merge`, the HLD's grants and `costs:` decide who runs
`swarm.sh merge --board` (§ Merging). `merge --board` runs no codex for any kind and keeps its CI
gate: a PR whose head is not green is refused.

When `done` clears a plan PR that closed unmerged, it also removes `.swarm/<hld or epic>/critic.json`
and names it. `hooks/lead-stop.sh` reads that file as a plan reported and waiting on the user, but a
closed PR leaves nothing to wait on. A file newer than the branch's last commit belongs to a new plan,
so `done` keeps it.

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
`swarm.sh merge` holds for them (§ Merging). It prints one line per item and logs one `lead-woken` line for each in events.tsv,
with the line's kind in the outcome (`ok (held)`, `ok (no-agent)`).
A review item's line is `merge: <slug> <PR URL>...`. The PRs of an item that `swarm.sh merge` held
because they change a protected path go on a line of their own, without the item's other PRs, with
their paths and the exit: `merge: <slug> <PR URL>... (held: changes <path>[, <path>]...; exit: the user
merges it)`. A PR whose files could not be read is held too, and its line says `its files could not be
read: <why>` in place of the path. `status` lists those PRs on their own row, `awaiting your merge
(protected path): <slug> <PR URL>...`, and the item's other PRs on its untagged row. A PR that
`swarm.sh merge` held because its own merge of the base dropped base lines gets a row of its own too,
`awaiting your merge (dropped base lines): <slug> <PR URL>...`, apart from any protected-path PR of the
item. Its line names what was dropped and who fixes it: `merge: <slug> <PR URL>... (held: dropped base
lines: <n>, first <file>: <text>; exit: the builder restores them in a commit of its own, or the user
reads the PR's answer and merges by hand)`. When the check could not run, the line gives the reason and
a different exit: `(held: dropped base lines unchecked: <why>; exit: the user checks the merge by hand
and merges it, or runs swarm.sh merge again)`. A held PR that a
story and its epic both list is printed once, under the first item, and left off the other's line. A
hold names the head it was read at, and each heads pass first reads the head of every PR a hold names,
story PR or not. Once a pass made after the hold reads the PR at another head (the builder pushed), the
hold stops counting, and the PR is no longer listed as held until a `swarm.sh merge` reads it again.
It also prints `next`'s `idle:` lines: for blocked stories (`idle: <story> waits on <dep> but shares
no touches part with it and needs nothing from it`) and for ready stories with no build (`idle: <story>
is ready with no build, exit: <exit>`), and the epic lines (`idle: epic <epic> can start, ...` and
`idle: epic <epic> has no plan running, ...`). Each poll works them out again from the board, its
state and events.tsv, with no gh or herdr call. A line wakes the lead once and goes once its dependency is in
review or done, once the story's build starts, or once the epic is active with stories or its plan runs. It wakes the lead again only if it comes back. A
ready story's line names its exit, so when the story's conductor starts or stops, the line changes,
and `wait --lead` takes the changed line as new and wakes the lead again. On a run that starts with no
`.swarm/lead/seen`, the first read saves the lines it finds without waking the lead, as it does held
lines, so a line already there wakes the lead only when it leaves and comes back. A poll whose check
fails keeps the lines the last poll saw and prints one `warning: the idle check failed` line
on stderr in place of a traceback, so a check that keeps failing warns on every poll. `status` lists the same lines under its Next section, with the same
warning when the check fails, and `dash` in an `idle capacity` box.
The PR heads are read with gh only on a run's first read and then at most once every 5 minutes
(`SWARM_LEAD_HEADS_EVERY`, 300 seconds). Each of those reads writes every review item's result to
`.swarm/lead/heads`, the open story PRs to `.swarm/lead/prs` and each base's CI to `.swarm/lead/bases` (both below). The polls in between read only those files and make no gh call. A PR in review
therefore wakes the lead up to 5 minutes after its head turns green. A story that enters review
waits for the next read of the heads. So does one that leaves review and comes back: a poll that
finds a story out of review drops its result from that file.
After a merge the heads pass runs on the next poll: a `merge` line added to `.swarm/events.tsv` since the
last poll brings it forward. A story whose PRs have all merged since its build last started gets no line,
though its file stays on the board until reconcile. A `merge` event that ends `ok` or `merged elsewhere`
and names the PR counts as its merge, and so does one that names a story with one PR. A heads pass that
reads a PR as merged on GitHub counts too; it reads the PRs of the items awaiting a merge by you.
The lead handles each line at once and starts it again. It keeps what it last saw in
`.swarm/lead/seen`, so an item that lands between two runs wakes the next one. A new run stops
any earlier one, so only one is ever watching. It edits the board only to write the fix-main story of a red
base, through a run of its own, and to retire that story once the base reads fixed (both below).

**A story PR left unmerged, or conflicting with its base, wakes the lead too.** The same heads pass that
reads the PR heads (on a run's first read, then at most once every `SWARM_LEAD_HEADS_EVERY` seconds) lists
the open PRs of every repo the board's stories name: the project's own, and each story's `repo:`. Each repo
costs one `gh repo view` a run, to find its owner and name from its origin as `swarm.sh watch` does, and one
`gh pr list` a pass. Each gh read is cut off after 30 seconds (`SWARM_LEAD_PRS_WAIT`) and then counts as
failed; so is each PR head the pass reads, a held PR's included, and a head it could not read leaves the
hold standing. The pass writes what it read to `.swarm/lead/prs`, and each poll joins that file with the board as it
is then, with no gh call. A PR counts when it is an open `story/<slug>` PR in its story's own repo, and its
story is ready or in review and is one an agent builds (never a `lead` story's), under either merge mode and
whether a builder is at work or not. For each one it prints:

- `unmerged: <slug> <PR URL>, exit: swarm.sh merge --head <sha> <PR URL>` when GitHub reads the PR as
  mergeable, its checks are green, `.swarm/reviews/<slug>.md` is a pass on its head (as `review_pass` reads
  it), and the PR was opened and that file last written `queue_minutes` or more ago. `<sha>` is that
  reviewed head, so a push after the line leaves merge refusing the PR. When the file lists findings, the
  exit is `triage .swarm/reviews/<slug>.md, then swarm.sh merge --head <sha> <PR URL> once every finding is
  declined`: a pass means only that a review finished on the head. Green here is narrower than
  `ci_gate`'s rule: every check run and status in the rollup GitHub returns passed (success, skipped or
  neutral), with at least one check run. A required check that never reported is not seen; `swarm.sh merge`
  runs the full rule. There is no `unmerged:` line for a kept story's PR (its `kept:` line comes first), for
  a PR that already has a `merge:` line, or for one a running `swarm.sh merge` is merging, such as a PR
  waiting in a merge queue (one `ps` read, only on a poll that has such a line due). When that `ps` read
  fails, nothing says whether a merge is running: the PR keeps the `unmerged:` line it had in
  `.swarm/lead/seen`, and gets no new one until a poll reads the process list again.
- `conflict: <slug> <PR URL>, exit: tell its builder to merge the base in` when GitHub reads the PR as
  conflicting with its base, which runs no checks on it. A PR with a `stuck:` line gets that line instead.
- `stuck: <slug> <PR URL> (<findings|conflict> pending <N> min), exit: swarm.sh tell <slug> resume <file>`
  when the story's builder has sat on a pending item for N minutes on the same head. N is 60
  (`SWARM_STUCK_MINUTES` overrides it). The item is either findings told to the builder (an `events.tsv`
  `tell` or `tell:findings` line that went through since the build started), counted from the newest one,
  or a conflict with the base, counted from when a poll first saw it on that head. A push resets both. A
  head whose review passed (`.swarm/reviews/<slug>.md` is a pass on it) has no pending findings, since the PR
  then waits on its merge. A conflict on such a head is still pending. The builder must also be live in
  the poll's herdr list and idle, with no background task in its session and no test suite running in its
  pane (`make test`, `make check` or `scripts/test.sh`). `.swarm/lead/pr-heads` keeps each open PR's head
  and when a poll first saw it. Findings told before then do not count, so a head seen first after a long gap
  in `wait --lead` waits for its next findings. The line names N, never the minutes that passed, so it
  reads the same on every poll and wakes the lead once. When herdr's list or Claude Code's list of sessions
  cannot be read, the PR keeps the `stuck:` line it had in `.swarm/lead/seen`. An `UNKNOWN` mergeable state
  keeps it too, but only on the same head.

A line wakes the lead once, and again only after a poll finds it gone and it comes back. Each is an alert: a run that
starts with no `.swarm/lead/seen` prints them on its first read, since nothing else shows them. As the
file is a heads pass's, a line comes up to 5 minutes after its PR changes. A PR whose mergeable state
GitHub has not worked out yet keeps the lines it had in `.swarm/lead/seen`. So does each story of a repo
whose read failed. When a repo's read fails on 3 heads passes in a row (`SWARM_LEAD_PRS_WARN_AFTER`),
`wait --lead` prints one `warning: wait --lead could not read the open PRs of ...` line on stderr. The lead
clears it: check `gh auth status` and that gh can see the repo. A repo with no clone or no origin has no
PR to list.

**A red base wakes the lead too, whoever merged into it.** The same heads pass reads the base of the
project's repo and of each repo the board's stories name, picked as a build picks it: the first
`base_branches` entry GitHub has, else the repo's default branch, asked once a run. It also reads the base
of each red main still logged in events.tsv. For each base it reads the head commit (cut off after 30
seconds) and that commit's CI (cut off after 60 seconds), and writes what it found to `.swarm/lead/bases`.
The CI is green when every check run and commit status passed, with at least one of either: a base may post
only statuses. A head whose CI is pending, has no check run or status yet or could not be read is read again on
the next pass, and so is a red one. A green head is read again for 2 hours, so a rerun that fails on the
same commit still counts. After that it is read again only once the base moves, unless a rerun was seen
under way: that is read until it concludes, however long the head has stood. A read that fails keeps
what the last pass found, even once the base has moved on to a head whose CI it could not read. So does a
repo gh could not name, a base it could not tell (nothing reads the branch it had, which may be the base no
longer), and a rerun under way on a red head. A repo with no clone or no origin cannot be read by any pass, so
its lines go, as its PRs' lines do. Each poll then prints, with no gh call:

- `main-red: <short sha> <owner/repo> <base> (<red checks>), exit: <exit>`, one line per red base: the red
  main logged there (`main-red` in events.tsv, by `swarm.sh merge` or by the run below) that no `main-green`
  has cleared, else the head the last pass read red there. The checks are the red ones alone, cut to 300 characters. A head
  read red again keeps its line as first read, so a check that finishes later does not wake the lead a
  second time. The exit follows the base's fix-main story:
  - `fix-main-<short sha> waits on the lead: handle its held: or escalated: line` when it is held or
    escalated.
  - `wait for fix-main-<short sha>, whose build has started, to merge` once its build has begun, or it is
    in review.
  - `build fix-main-<short sha>, which next names first` while `next` would name it: ready, one an agent
    builds, and no build begun. When two such stories stand, `next` names the newest red's first, and each
    other's exit is `build fix-main-<short sha>, which next names after fix-main-<that one's short sha>`.
  - `fix-main-<short sha> is not one next builds: check its status and kind` for any other story.
  - `wait for fix-main-<short sha>, which a fix-main run is writing and next then names first` when there
    is none yet and the run below is writing it or waits to start. The line changes, and wakes the lead
    again, once the story is there.
  - `read .swarm/lead/fix-main-<short sha>.log, as no run wrote fix-main-<short sha>, then fix <base> by
    hand` once 2 runs failed. This is the lead's check: the log says why each run failed.
  - `fix <base> by hand, as no fix-main story covers it yet` when there is none and no run writes one: the
    red's story has left the board, or the head is red only on checks the base does not require (below).

**A red base head gets its fix-main story from a run of its own.** On each poll, for each base head the last
pass read red that no `main-red` covers (none logged, or one a `main-green` has cleared), `wait --lead` starts
`swarm.sh _fix-main <repo> <base> <sha>`. `<repo>` is the board's name for the repo, `.` for the project's
own. The run is detached in a session of its own and pinned to the project, so it goes on after `wait --lead`
returns or a new run stops it. Its output goes to `.swarm/lead/fix-main-<short sha>.log`. It reads the base's
head again (cut off after 30 seconds), then that commit's CI (cut off after 60 seconds) for the red checks
and their URLs. Then it writes the story as `swarm.sh merge` does (§ Merging), with its log reads cut off
after 60 seconds, and logs `main-red`. The story says no `swarm.sh merge` wrote a fix for the red, and names
no merged story. When the base has moved off that commit since the pass, or its CI now reads green or
pending, the pass's read is out of date: the run writes nothing, and its log's last line starts `stale:`.
Such a run does not count as a failed one. No run starts for that head again until the next heads pass has
read the base. A head red only on checks the base does not require gets no story either: before it writes,
the run asks `ci_gate fixed` whether the head is its own red's fix, as the next pass's clear would, and when
it is, the log's last line starts `not required:`. That run does not count as failed, and no run starts for
that head again. When none of the red checks is one the base requires, and a required check is still
running, whether the red is one the base requires is not known: that run writes nothing either, and ends
`stale:` as above. When a required check has no run yet, the run ends `absent:`, naming it. That run counts,
and the next starts only after the next heads pass, so a required check that never reports on the base ends,
after 2 runs, in the lead's check, never in an endless wait. No run starts while one for that head is running, or while `ps` shows a `swarm.sh merge` of
a PR in that repo. `ps` shows neither the merge's base nor its project, so any such merge holds the run back,
since the merge's own fix may log the red. Any other run that ends with no `main-red` logged has failed, and
the next poll starts another. One still running after 10 minutes is stopped, and counts as failed. For each
run it stops or counts as failed, `wait --lead` adds a line to the log, since a killed run writes nothing of
its own there. After 2 failed runs no more start. A repo `wait --lead` cannot name (no story names it, or gh
failed) gets no run, and its line stays as it was, so a gh failure wakes no one; a later pass that names it
starts one.
What each head's runs did is in `.swarm/lead/fixes`.

When a base with a logged red main reads green, or red only on checks the base does not require, the pass
clears it as reconcile does (§ Merging): once that head shows the red fixed (`ci_gate fixed`, which judges
the required checks alone once each has a run), it logs `main-green` and retires the red's fix-main story
if nobody has started it, and the line goes on that poll. With such an optional check still red, that poll
prints the head's own `main-red:` line for it, with the by-hand exit, since no story covers it. A red the pass found itself goes once the base's head reads
green, or moves to a head whose CI is read. The line is an alert: a run that starts with no `.swarm/lead/seen` prints it on its first
read. As the file is a heads pass's, a line comes up to 5 minutes after CI on the base finishes. When a
base's read fails on 3 heads passes in a row (`SWARM_LEAD_PRS_WARN_AFTER`, the same count as the open PRs'),
`wait --lead` prints one `warning: wait --lead could not read CI on <base> of <owner/repo> ...` line on
stderr, or `could not tell the base of <owner/repo>` when it could not pick the base. The lead clears it:
check `gh auth status`, that gh can see the repo, and `base_branches`.

**A brief left in an idle agent's input box is submitted once.** herdr types a long brief into the
pane as a collapsed paste (`[Pasted text #1 +40 lines]`), and an agent can sit idle with it still in
its input box. On each read, `wait --lead` takes the agents this project opened that the read's one
herdr list shows idle. For each one it finds the newest `events.tsv` line that gave the agent a
prompt. That is `story`, `escalate` (a ladder step-up), `step-up`, `restart` or a `tell` of any kind
but `note` for the builder, `review-agent` for `review-<slug>`, `conduct` for a conductor, and `agent` for an
agent started by name. The line must end `ok`, or in deliver_prompt's error after herdr sent the
prompt or may have (`herdr sent it the brief`, `may or may not have the brief`, `could not be
read`), which is how a brief that was never taken up ends. A tell that failed before sending
delivered nothing, and the line before it counts. A start that failed before sending leaves its
agent alone: it may have opened the pane and recorded a new session with no turn in it, so its box
holds no older brief. A note (`tell:note`) goes to a conductor's inbox, and the prompt that wakes
the conductor is one line, never a collapsed paste. If that line is new, it reads the agent's pane
once. The read and the Enter each get 10 seconds, and no read starts 20 seconds into the pass (the
rest wait for the next read), so a hung herdr cannot hold up the items the read found for the lead.
It sends the pane Enter (`herdr pane send-keys <pane> Enter`) and logs `resend <agent>` when the
input box holds the paste and no turn has started since the brief went out. A turn start is a prompt
in the agent's Claude session log (not a tool result or a `/goal`). An agent with no Claude session
on record, or no log of it, is left alone: Claude Code writes the log before the first prompt, so a
missing one says nothing. Its pane is read again on the next read. A start opens its own session, so
any turn start in it counts. The line is written only when its command returns, so for a tell any
turn start later than seven times `PROMPT_TIMEOUT_MS` (7 minutes) before the line counts. A tell
sends nothing to a working agent (it queues the tell). Each of deliver_prompt's two tries can wait two `PROMPT_TIMEOUT_MS`, and
with `goal` on the findings' `/goal` can wait two more. So a tell sent within 7 minutes of a turn
start is left alone: the log cannot tell that turn from one the tell started. An agent that took the
brief has had a turn, so a later, unrelated paste is left alone. A paste in a prompt already
submitted above the box does not count either. Each line it is done with goes in
`.swarm/lead/resend`, and the pane is not read again until a newer line comes, except once after
an Enter (the `.unsent` marker, below). Before the Enter the
line goes in marked `pending`, which does not count as done, and a line it cannot write gets no
Enter. A run stopped before its Enter is tried again by the next read, which reads the box first, so
a brief that did go is not sent twice. A failed read, a check that fails unexpectedly, or an Enter
herdr could not send (its line stays `pending`), notes nothing, so the next read tries again; the
failed Enter is logged as the `resend` line's outcome. A working agent's pane is never read. Nor is
the pane of an agent that a `swarm.sh` command is still delivering to: a `story`, `tell`,
`review-agent`, `conduct`, `step-up` or `agent` naming it, and for a conductor any `next` or
`merge`, which start conductors. That command's new line is not written yet, and an Enter could
submit the brief it is sending. The process list is read again just before an Enter, and the Enter
waits for the next read if `events.tsv` gained a line while the pane was read, since that line may
be a newer delivery. While an upgrade runs, which restarts agents, no pane is read at all. It never
resends through `tell`, which would log a second `tell:findings` line and count a review round
twice. The resend prints nothing and wakes no one. The stall rule skips `resend` lines. A brief
still in the box on the read after the Enter wakes the lead through an `.unsent` marker (below).

**An agent stuck where no agent can help wakes the lead too.** `wait --lead` prints
`prompt: <agent> (<kind>), exit: <exit>` for an agent this project opened that its one herdr list
shows blocked, idle or done, and whose pane shows it stuck. A working agent's pane is never read. These
are skipped: a retired agent (`<name>-done`), a co-writer that talks with you in its own pane (an
`agents.tsv` role of `hld` or `epic`), and an agent a `swarm.sh` command is delivering a prompt to, as
the resend skips it. While `swarm.sh upgrade` runs, no pane is read, as for the resend.

The check runs after the resend and shares its budget: 10 seconds a read, and none started 20 seconds
into the poll's reads. A pane the resend read in that poll is not read again, and one it failed to read
waits for the next poll. `.swarm/lead/stuck` keeps, for each agent, its herdr status, the time its
Claude session log last changed, what its pane showed and when it was last read. A pane last found
clear is read again when the status or the log time has changed, or after 5 minutes
(`STUCK_RECHECK`), since manual mode turned on or a dialog opened at an idle box changes neither. A pane
last found stuck is read every poll, since you can clear it without a turn. Agents are read oldest read
first, so slow reads that use up one poll's budget leave the rest first in line for the next. Each
poll's first read of its own goes even past the budget, so a loaded machine still reads one a poll.

The kinds and their exits:

- `prompt`: a permission prompt, a menu or a dialog waits on an answer, with no command running
  under it. Exit: `the user answers it in pane <pane>`. Claude Code's usage-limit dialog is not one:
  `wait` answers it.
- `login`: the turn ended on "Please run /login". Exit: `the user runs /login, then swarm.sh tell
  <agent> resume <file>`.
- `api-error`: the turn ended on Claude Code's `API Error:` line. It comes only while no
  `swarm.sh wait` naming the agent runs, since a running `wait` resumes it and ends once it gives
  up. Exit: `herdr agent read <agent>, then tell the user what it shows`.
- `manual`: the footer under the input box says manual mode. Exit, for a ready story's builder:
  `herdr pane close <pane> then` the restart or hold a `no-agent:` line names (restart refuses a
  builder herdr still lists). For any other agent: `the user turns manual mode off in pane <pane>`.
  A permission prompt with that footer under it (a builder in manual mode is nearly always on one)
  is `manual` for a ready story's builder, whose restart clears both. For any other agent it is a
  `prompt` whose exit adds `, and turns manual mode off there`.

The line wakes the lead once per stop. It stays in `.swarm/lead/seen` while the agent is stuck. A
skipped agent, a pane read that fails, and a herdr list, list parse or `ps` that fails all keep the
last poll's line, so a missed read neither drops it nor wakes the lead again. A new stop wakes the lead
even when its line reads the same: one found after the agent moved on, after a turn (its session log
changed), or in a pane the agent came back in. Manual mode is a state, not a stop, so a builder in it
answering prompt after prompt wakes the lead once, and its line stays while it works between them. A
pane the resend sent Enter to in a poll is left for the next poll to read.

**A started story with no agent wakes the lead too.** `wait --lead` also prints
`no-agent: <slug>, exit: <exit>` for a story whose build started and that nothing works on. It
counts a story only when all of these hold:

- It is ready, or in review under `merge = agent`. A story waiting on the user is left out:
  awaiting their merge under `merge = human`, `costs: money` or `kept:`, green or not. A story in
  review under a `merge` grant counts until an ok close ends its builder's newest start, as the
  handover's close does; after that it gets only the `no-review:` line (below).
- It is of a kind an agent builds. That rules out `kind: lead`, and so every held or escalated
  story. A blocked story is never counted.
- It has a build record: an ok builder start that no close ended or, for a story with any start
  line, its worktree or `story/<slug>` branch.
- No `swarm.sh upgrade` runs in this project for its epic, its backlog or every agent: an upgrade
  stops agents and starts them again. Its ok events line counts as a start, except for a story
  reconcile reopened: an upgrade restarts only running agents, so that story stays left out.
- herdr lists no pane this project opened under its builder's name or `review-<slug>`. No
  `swarm.sh wait-pr` or `swarm.sh merge` runs on its PR.
- No tell is pending. While a `tell`, `story`, `agent`, `review-agent`, `step-up` or `restart` command runs for
  the slug, its answer is still on the way: each writes its own events.tsv line when it exits.
- A ready story has no `.swarm/briefs/<slug>.step-up` marker. A failed step-up has a line of its own
  (below).

Something must explain why no agent is there: an ok close of the builder or the review agent, or a
failed start, with no later start, ok tell or hold. A story reconcile reopened (its PR closed
unmerged) is left out until a new start: `unblock --startable` already names it for the lead, from
the reopen being its last events line, which a line written here would hide. When a pane went with
no such event, the poll that first sees it writes a `no-agent <slug>` events.tsv line and stays
silent, and the next poll wakes the lead. The exit for a ready story is
`swarm.sh restart <slug>, or swarm.sh hold <slug> <reason>`. Restart brings the builder back in its
worktree, so the next poll is quiet. A story that restart would refuse gets `swarm.sh hold <slug>
<reason>` alone: one held until its parents merge (`held_by:`), one whose worktree is gone and only
its branch is left, or one with no builder in `.swarm/agents.tsv` (its first start failed before the
builder was recorded). A hold answers the alert but starts nothing, so if no agent is
back by the next poll, that poll writes a new `no-agent` line and the alert comes back. For a story in
review the exit is never an unpinned merge. With one PR and a findings file
`.swarm/reviews/<slug>.md` that passes on its 40-hex `head:` line, it is
`swarm.sh merge --head <sha> <PR URL>`, which refuses a head that moved since. With several PRs, or
no passing review, it is `swarm.sh review-agent <slug> <PR URL>` for
each. The lead runs `swarm.sh wait-pr <PR URL>` first and acts on its exit, once per head. On 0 it
compares the head wait-pr printed with the exit's `<sha>`: the same, it merges; different, the PR was
pushed after its review, so it runs `swarm.sh review-agent <slug> <PR URL>` instead, since merge
refuses the old pin and the line, already seen, would not come back. On 1 (red) it starts a builder in the story's worktree with a brief naming the failing
checks, or lists the story in its report with the reason, since `swarm.sh hold` takes only a ready
story. On 2 it reads why: on a conflict with the base, a builder in the story's worktree merges the
base in and pushes; on a gh error or the timeout, it runs wait-pr once more, and if it ends the same
way, lists the story in its report with the reason. On no check runs, or an expected workflow that
never started (wait-pr names it), it reads the checks once with `gh pr checks <PR URL>`: a builder
fixes a workflow that failed to start, else it runs wait-pr once more, and if that ends the same way,
it lists the story in its report with the reason. A story in review with no PR URL gets the exit
`gh pr list -R <the story's repo's origin> --head story/<slug>, then swarm.sh review-agent <slug> <PR URL>`. The line is quiet
while wait-pr runs and may come back once after it ends.

**A review agent that never started, or started and went, wakes the lead too.** `wait --lead` prints
`no-review: <slug> <PR URL>, exit: swarm.sh review-agent <slug> <PR URL>, or the fallback reviewer`
for a story that passes the `no-agent:` filters on status, kind, `held_for:`, `kept:`, `costs:`,
upgrades and a ready story's step-up marker, that has a build record as `no-agent:` needs it (an ok
builder start no close ended, or its worktree or `story/<slug>` branch), and whose review start is
on record: a `review-agent <slug>` events line since its last ok `story` start or reopen. A build a
close cleared has no PR left to review. It comes whether or not the builder is listed. Under
`merge = human` it also comes for a story in review when the agreed HLD over it grants `merge`. The
lead merges that PR once it is reviewed, so a review agent gone leaves it unreviewed. The grant is
read from the board (the story's epic, its parents and the HLD), with no gh call. Once an ok close
ends its builder's newest start, as the handover's does (the review agent's `swarm.sh review`, then
the conductor's `close` on the note it sends), such a
story gets no `no-agent:` line, and the lead's `merge:` item covers the PR. Until then, a builder
gone with no close still gets its `no-agent:` line: one whose pane died before the handover, or one
started again since to fix a later review's findings. For that one the findings round keeps
`no-review:` quiet, so `no-agent:` is the only alert. One of these must hold:

- Never started: the newest `review-agent <slug>` line is not ok.
- Started and went: that line is ok and `.swarm/reviews/<slug>.head` was written, but no findings
  file passes on that head (as `review_pass` reads it) and no ok `close review-<slug>` line came
  since the start. A close is an act of the lead's or reconcile's, never a
  review agent's own end.

A refusal that leaves an earlier ok start of this build running, with no close since, changes nothing: `review-<slug>`
still reviewing, or its name still held. That review's own end decides. With no such start, the
name is held by something else (another project's agent, say), and the refusal counts as a failed
start.

It stays quiet while a round is under way:

- herdr lists `review-<slug>` in a pane this project opened;
- a findings round came after the newest review start in events.tsv, so the builder is fixing what
  it was told. A findings round is a findings tell that is ok or that herdr sent, or a findings
  step-up (`escalate ... ok (findings-N: ...)`), as the review round count reads them. An ok
  `review-agent:next` line (`review-agent --next`, the review agent's next round in its own session)
  counts as a start, so once it runs the review agent owns the PR again. A failed one started no
  round and changes nothing;
- that start was refused because the builder is still at work (its worktree not at the PR's head,
  or with uncommitted changes), and a findings round is on record;
- a process answers for the story, as for `no-agent:`: a `tell`, `story`, `agent`, `review-agent`,
  `step-up` or `restart` naming it, or a `swarm.sh wait-pr` or `swarm.sh merge` on its PR, on
  `prs:` or on the PR its review brief names.

The PR comes first from a failed start's message, unless that message refused it as not a PR URL.
It counts only when `prs:` is empty or holds it. Next comes the first line of
`.swarm/briefs/review-<slug>.md`, but only when the newest start wrote that brief: an ok start, or
one that failed after it (did not start, a start that was unclear, a brief taken before an expired
login, or a failed `mktemp`). A preflight that fails before the brief is written leaves an earlier
attempt's brief, which may be for another PR. Last comes `prs:` when it holds one URL. With no PR,
the line is
`no-review: <slug>, exit: gh pr list -R <the story's repo's origin> --head story/<slug>, then swarm.sh review-agent <slug> <PR URL>, or the fallback reviewer`.

**`wait --lead` starts a review agent again when its start was cut short.** `review-agent` makes up
to 3 starts itself, and logs each try as it begins, before the brief goes out, as
`review-agent:try <slug> (try N of 3) started`. A command cut off partway, by a conductor's tool
timeout for example, leaves tries unused. For a story that gets a `no-review:` line, the poll reads
its `review-agent`, `review-agent:try` and `review-agent:restart` lines since its newest ok `story`
start or reopen, or its newest ok `review-agent` start. The tries spent are the highest try number
on record. It starts the next try when all of these hold:

- the newest outcome is a start that ran nothing (a `review-agent` line ending `(try N of 3)`) or one
  of the poll's own restarts, and a trailing `interrupted` line changes nothing;
- fewer than 3 tries are spent;
- the PR is known. The poll takes it from the brief, which the cut-off command wrote, ahead of
  `prs:`, which may still name an older PR. With no brief it uses the sources above.

It first logs `review-agent:restart <slug> started (try N of 3)`, then runs
`swarm.sh review-agent <slug> <PR URL>` detached, starting at that try, with its output in
`.swarm/lead/review-<slug>.restart`. Two polls overlap only while a new `wait --lead` takes over.
Then the lock `.swarm/lead/review-<slug>.restart.lock` lets one of them start it, and the restart's
pid, in `.swarm/lead/review-<slug>.restart.pid`, keeps the other from starting the next try while it
runs. A poll killed while it holds that lock leaves it behind, and the story's line then comes with no
restart until you remove it. The line reads
`no-review: <slug> <PR URL> (started N of 3), exit: swarm.sh review-agent <slug> <PR URL>, or the fallback reviewer`.
While that command runs, the next poll is quiet, as for any `review-agent` naming the story. A
restart killed before its command logs a line still spends its try, so the poll stops at 3 starts in
all.

A try that began and has no outcome, because its command was interrupted or killed mid-start, may
have sent the brief. The poll never starts it again, and the line names the check:
`no-review: <slug> <PR URL> (try N of 3 was cut off mid-start and may have sent the brief), exit: check that no pane holds review-<slug> (swarm.sh status, then swarm.sh tidy for an empty one), then swarm.sh review-agent <slug> <PR URL>, or the fallback reviewer`.
Any other case prints the line as above. `next`, `status` and `dash` print the same lines but start
nothing: where the poll would start the next try, they print the line with no `(started N of 3)`.

A story whose `no-agent:` line printed in the same poll gets no `no-review:` line, because that
line's exit comes first. In review it already names `swarm.sh review-agent`. For a ready story the
restart brings the builder back, and the next poll prints `no-review:`. The exit starts `review-<slug>`, so the next poll
is quiet. When no review agent can start, the exit's `or the fallback reviewer` means the lead
reviews the PR itself with `swarm.sh codex-review`, run from the story's worktree (codex-review
reviews the directory it runs in) with `SWARM_STORY=<slug>`: codex, or at codex's usage limit the
model `fallback_reviewer` names. The lead runs it only while the worktree is at the PR's head with
nothing uncommitted, as `review-agent` checks; otherwise the builder is still at work. Its findings
go to the builder with `swarm.sh tell <slug> findings <file>`, which is a round under way, so the
line goes quiet. A clean run clears nothing: the line stays in `status` and on the dashboard until a
review agent starts on the PR, findings go to the builder, or the PR merges and the story leaves the
board. The line reads the same herdr list, events.tsv and `ps` as `no-agent:`, with one more read of
events.tsv for the stories with a build record, one more for each story that gets the line, and no gh
call.
With no PR known, it runs `git remote get-url` on the story's repo for the exit.

Each poll reads `herdr agent list` once, killed after `SWARM_LEAD_LIST_WAIT` seconds (default 30): a
hung herdr counts as a failed list, and the other lines still wake the lead. Front matter and
events.tsv are read every poll; git only for a story with a start line and no current builder; herdr's
JSON and `ps` once, whenever a story with a build record or a ready story with a step-up marker is
left after those reads, before the listing is checked. No gh call is made for these lines. Outside
herdr, or when herdr's list or `ps` fails, it prints none. A run with no `.swarm/lead/seen` yet prints
these lines on its first read, and every other line except `held:`, `escalated:`, `kept:`, `merge:` and
`idle:` lines, `tell undelivered:` and `tell goal failed:` lines (§ A tell to a busy agent is queued)
included. Other commands already show those five, so the first read notes them without printing them.

**A review agent's stop note that no conductor has wakes the lead too.** A review agent that stops
writes its note to `.swarm/reviews/<slug>.stop.md` and tells it to the story's conductor (§ Building).
`wait --lead` prints
`stopped: <slug> (<the note>), exit: act on its why as <conductor>'s review rule says, or start a conductor for the story and send it the note with swarm.sh tell <conductor> note <file>`
for each such file whose story is on the board and not done, once the note is 120 seconds old
(`SWARM_STOP_GRACE`), unless a conductor has the note. The agent writes the note, then tells it a
model turn later, so a younger note may be on its way to its conductor. A
conductor has it only when the note's `tell` reached it: `tell <conductor> note` then leaves
`.swarm/reviews/<slug>.stop.told` naming the conductor. That conductor must still run in a pane of
the poll's herdr list with no report written, and must not have been started again since, because a
new start clears its inbox. So a note whose tell failed comes to the lead even after a conductor
starts for the story, and so does one that reached a conductor that has since stopped. A story in
review whose PR waits on the user's merge gets no line: under `merge = human` with no `merge` grant,
one that costs money, or one whose merge `held:` it for the user. An `unconfirmed` merge, or one to
check by hand, goes to the lead, so its note does get a line. `review-agent` removes the note when it starts a new agent, so the line goes
then; a start that fails with no agent running puts the note back. It reads the same herdr list as
`no-agent:`; a poll whose list failed keeps the `stopped:` lines it saw last.

**A conductor that reported with agent work left wakes the lead too.** A conductor writes
`.swarm/conduct-<epic>.report.md` as its last act, and a new `swarm.sh conduct` removes an earlier
run's report before it starts, so a report on disk is the newest run's. For each one, `wait --lead`
prints:

- `reported: <epic> (<n> stories still an agent's), exit: swarm.sh conduct <epic>` while a story of
  the epic is still an agent's, by the rule the `finish:` line uses (§ Merging): ready, blocked on
  an agent's story, or in review with a review agent still to act. `<n>` is how many such stories
  there are. It includes two kinds the conductor's brief has it list for the lead: a build that
  died and a `not held:` line. For the backlog
  conductor's report, `conduct-backlog.report.md`, the line counts the stories with no epic and
  reads `reported: backlog (...), exit: swarm.sh conduct --backlog`. The conductor stopped with
  work left, and the exit starts a fresh one. Collect a conductor still in its pane first, since
  the exit retires it and deletes its report. Then read the report: a new conductor cannot clear
  the stories it lists for the lead, so clear those first (`commands/swarm.md`'s wait arm says
  how). The line makes no herdr or gh call. It reads the board, `.swarm/board-state`, `events.tsv`,
  the tab records and the story worktrees. A report whose group no story's `epic:` line names is
  skipped without reading further, unless a fix-main story is on the board. The line goes once
  that work is done or a new conductor starts.

**Builders that cannot sign their work wake the lead too.** `wait --lead` prints one line for all of them:
`sign-blocked: <slug>, <slug> (their signing key is locked; unsigned work in their worktrees), exit: unlock your signing key in your shell (gpg-agent or ssh-agent), then swarm.sh tell <slug> resume <file> for each`.
A builder is on it when four things hold. Its newest `sign-blocked:` or `sign-clear:` incident in
`events.tsv` is a `sign-blocked:` one. It still runs in a pane of the poll's herdr list. Its worktree still
has uncommitted work (`git status --porcelain`). Its worktree's last commit is still the one the incident
names in `unsigned work since <time>`. The probe runs only on a builder that looks stalled, so a builder
that was unblocked and went back to work gets no `sign-clear:`; a commit since the incident shows it
signed. Each git read runs with
`GIT_OPTIONAL_LOCKS=0` and is cut off after 10 seconds, so a read that is cut off leaves no `index.lock` to
fail the builder's next commit. A read that fails or is cut off says nothing either way: the builder stays
on the line if the line the last poll saw names it, and is left off if not. A builder whose worktree is
gone leaves the line. The slugs are sorted, so the
line reads the same from poll to poll and wakes the lead once. It changes, and wakes the lead again, when a
builder joins or leaves it. The poll asks no signer: it runs no gpg, gpg-connect-agent, ssh-add or
ssh-keygen. The incidents come from the conductors' `wait --stall`, which probes the signer only once a
builder looks stalled (§ Building), so the line can come up to `stall_minutes` after the key locked. It
reads the same herdr list as `no-agent:`; a poll whose list failed keeps the `sign-blocked:` line it saw
last.

**A failed step-up wakes the lead too, through a marker file.** A marker is
`.swarm/briefs/<stem>.<kind>`, where `<stem>` names the agent's brief (the slug for a builder) and
`<kind>` says what it marks. Its first line holds the marker's own fields. A `pid <n>` line names the
swarm.sh process that wrote it. A later one-word line, such as `closed`, records a step the writer
got past. `wait --lead` reads `.step-up` markers in the same pass as its `no-agent:`
lines, from the poll's one `herdr agent list`, events.tsv and one `ps`, with no gh call. It reads
`.unsent` markers just after the resend, which writes and removes them. Outside
herdr, or while herdr's list or `ps` fails, it prints no marker line either: without the list it
cannot tell whether the builder is still open. It prints `<what>: <stem>, exit: <exit>`. The
`.step-up` marker works like this:

- Path: `.swarm/briefs/<slug>.step-up`. A step-up writes it just before it closes the builder,
  and removes it again if the close fails, since the builder may still be open. Once the builder
  is closed it writes it again with a `closed` line. A resume takes `.swarm/locks/step-up-<slug>`
  first, then writes it again with its own pid and `closed`, since a resume only follows a close.
  A resume refused because another step-up holds the lock leaves it as it is. It goes once the
  next model's builder has started.
- First line: `<trigger> <from> <to> <role>`, which `step-up --resume` reads to start the rung.
- Failure line: each point where a step-up stops after closing the builder logs
  `step-up:failed <slug>` with `ok (<why>)` in events.tsv. Those are an unreadable worktree, a git
  step left unfinished in it, an unread default branch, a failed `mktemp`, and a start that failed
  or that herdr could not confirm. A start that failed logs `ok (start failed)` whether or not the
  new builder's pane could be closed. Only the step-up's output says when the pane was kept, and
  it names the agent to read it by. Any other failure after the close, or of a resume once it holds
  the lock, logs it too. A failure with a die message logs that message's first line. One with no
  message logs only `ok (exit <n>)`, whoever ran the step-up: a `set -e` failure, or any failure of
  a step-up swarm.sh ran itself (from `close`, `tell`, `wait --stall`, `watch` or a review pane's
  `wait-pr`), which has no message to log. Its error is in the output of whatever ran the step-up:
  the conductor's pane for one `close`, `tell`, `wait --stall` or `watch` ran, the review agent's
  pane (`herdr agent read review-<slug>`) for one a review pane's `wait-pr` ran, the command's own
  output for one run by hand. `flow` reads the line as an ok line.
- Lead line: `step-up failed: <slug>, exit: swarm.sh step-up --resume <slug>`. It is printed for a
  story whose marker's pid is no longer a running `swarm.sh step-up` or `_step-up`, whatever the
  failure line or the `.swarm/locks/step-up-<slug>` lock says, so a step-up killed before it could
  log its failure line counts too. The process must name the slug, so a pid reused by another
  story's step-up does not count. While that process runs, the step-up is under way and the line
  stays quiet. It stays quiet too while herdr lists a pane under the builder's name and the marker
  has no `closed` line: the step-up stopped inside the close, so that pane may be the old builder,
  still at work. With the `closed` line that pane is the new rung's, kept by a start that failed
  or that herdr could not confirm, or left by a step-up killed after it opened the pane, and the
  line is printed. The resume's own start refuses the name while that pane's agent is working or
  waiting and retires it when idle, so it starts no second builder beside a live one. A marker gone
  by the time its pid is read is a rung that started, not a failure. The story must be ready, since
  only a ready story steps up, and pass the `no-agent:` filters on kind and `held_for:`. A story in
  review keeps to the `no-agent:` line, marker or not.
- Exit: the lead first reads the output of whatever ran the step-up, in every case. For a step-up
  swarm.sh ran itself that is the conductor's pane, and for one run by hand the command's own
  output. The failure line says where it stopped, and the output says why. With no failure line,
  the step-up was killed partway. With the cause fixed, the exit is
  `swarm.sh step-up --resume <slug>`. A pane may still be open under the builder's name, kept by
  the failed start or left by a killed step-up. The resume retires an idle agent in it and starts
  the rung (`swarm.sh tidy` closes the retired pane), and refuses while that agent is working or
  waiting, naming it. A working one took up its brief, so the lead tells the user instead of
  resuming again, since no swarm.sh command records that rung. The conductor leaves the story
  alone and does not list it in its report.

The `.unsent` marker works like this:

- Path: `.swarm/briefs/<stem>.unsent`, where `<stem>` is the brief's file name without `.md`: the
  slug for a builder, `review-<slug>` for a review agent, `conduct-<epic>` for a conductor and
  `conduct-backlog` for the backlog's conductor. The resend writes it, on the first read after its
  Enter, when the agent is idle, its input box still holds the paste and its session shows no turn
  since the brief went out. That read is made once per Enter. As before an Enter, the process list
  is read again first, and nothing is written while a `swarm.sh` command is delivering to the agent
  or when `events.tsv` gained a line during the read, since that line may be a newer delivery. An agent started by name with
  `swarm.sh agent` gets the resend but no marker: no command starts it again. deliver_prompt never
  writes it, since it has returned before the resend. A tell's marker takes the role of the
  agent's last start line (`story`, `review-agent` or `conduct`), or, with none, of the name it was
  told by: `conduct-<epic>` or the backlog's conductor is a conductor, `review-<slug>` a review agent,
  and any other name a builder.
- First line: `<agent> <pane> <role>`, the agent's herdr name, its pane and `builder`, `review` or
  `conductor`. Then `pid <n>`, the `wait --lead` that wrote it.
- Lead line: `unsent brief: <stem>, exit: <exit>`.
- Exit: for the builder of a ready story, `herdr pane close <pane> then <the no-agent: exit>`,
  which is `swarm.sh restart <slug>, or swarm.sh hold <slug> <reason>`. Its pane is closed with
  herdr, not `swarm.sh close`: on a ready story with no PR that close counts a failed attempt and
  clears the worktree, and restart then refuses. A builder whose story is in any other state, such
  as one in review whose findings sit in its box, is kept, since restart refuses a story that is not
  ready: the exit is `swarm.sh wait --idle <slug> && swarm.sh tell <slug> nudge <a file asking it to
  act on the brief in its input box>`, which herdr types after the paste and sends with it. With no story file the exit is
  `herdr pane close <pane>` alone. For a review agent it is
  `swarm.sh close review-<slug> then swarm.sh review-agent <slug> <PR URL>`, once per PR on the
  story (`<PR URL>` itself when it has none). For a conductor it is
  `swarm.sh close conduct-<epic> then swarm.sh conduct <epic>`, and for the backlog's,
  `swarm.sh close <its agent name> then swarm.sh conduct --backlog`.
- It goes on the read that finds its agent working, blocked or done, that finds herdr no longer
  lists the agent in that pane (an agent herdr lists with no status is still listed), or that reads its box clear or finds a turn started in its session
  since the brief went out (it took the brief, then got a new paste). Its line then leaves
  `.swarm/lead/seen` too. While the agent stays idle, its pane is read once each poll. A failed read
  leaves the marker as it is.

**`next` and `status` name it first too.** `next` reads the same `no-agent:` lines, without writing
an events.tsv line, and prints the first as its step, `no-agent <slug>`. A pane that went with no
event shows there once a `wait --lead` poll has written its `no-agent` line. The why ends with the
line's exit. The step comes after `fix-main` and before a conductor's `wait` or `collect`, since
the lead would otherwise wait on the conductor and never see the story. While a conductor works,
`next` still starts conductors for other ready work on this step, as it does on a `wait`.
`next` names each line once. It skips a line that `swarm.sh next` has already named
(`.swarm/lead/next-seen`, which only `next` run inside herdr writes) and goes on to the other steps.
So an exit that clears nothing, such as a merge refused on a red head, does not hold the lead's loop.
`next` forgets a line once a read that checked no longer has it (its agent came back, a hold), so the
line is named again if it comes back. A run that stopped at `fix-main`, or whose read could not
check, forgets nothing. `wait --lead` keeps its own record, so the lead may hear of a line from both.
Two `next` runs at once may both name the same line, and a `next` that cannot write the file still
prints its step. A `step-up failed:` line is never the step: `wait --lead`
hands that one to the lead. Working out the step makes no gh call, because `dash` reads it every
frame. `status` and `dash` hand `next` the lines they have already read, so neither asks herdr and
`ps` twice, and dash's Next row agrees with its No agent rows from outside a herdr pane too.

`status` prints a `No agent` section before its agents, one line per story: `<slug>, exit: <exit>`,
`<slug> (step-up failed), exit: swarm.sh step-up --resume <slug>` for a failed step-up, or the
`no-review: <slug> <PR URL>, exit: <exit>` line as `wait --lead` prints it for a PR whose review
agent never started or went, whose builder may still be at work. With no
such story it prints no section. It needs only herdr's agent list, so a failed pane list still shows
it, and the Agents line then says herdr gave no pane list. Outside herdr, or when herdr gives no agent
list, it says it did not check. It says so too when a started story is left to check and herdr's list
cannot be read or `ps` fails, so an empty section always means every started story has an agent. `hooks/lead-stop.sh` does not know the `no-agent` step, so it allows
the lead's stop on it.

**The lead is reminded to log what the user caught.** `/swarm-dev:swarm` tells the lead to run
`swarm.sh intervene user-caught <cause> "<what they found>"` as soon as the user finds a problem the
swarm missed. That rule lives only in the lead's prompt, and the lead forgot it: on 2026-10-25 the user
caught three problems and none was logged until they asked how such things reach the retro. So a
UserPromptSubmit hook (`hooks/user-caught-reminder.sh`) adds this line of context to each of your
messages to the lead: `If this message points out a problem the swarm or the lead missed, log it
first: swarm.sh intervene user-caught <cause> "<what they found>". The cause is one word from the
list in /swarm-dev:swarm; an unknown one fails and lists them.` It runs only in the lead's session,
found as the lead's Stop hook finds it (`hooks/lead-session.sh`): no `SWARM_AGENT` or
`SWARM_GH_CALLER` in its environment (every agent has one), a cwd outside any worktree, and a swarm
project. Anywhere else it prints nothing. It never blocks a message.

## Commands

**`/swarm-dev:swarm`**
Run everything after the design, stopping when a decision is yours.

**`swarm.sh board-pr start|open|done <name>`**
Make a board edit in its own worktree (`<repo>-wt/_board-<name>`) and open it as a PR.
It refuses a change outside the board, and never touches the main checkout.
The lead runs it for each board edit.

**`swarm.sh finish <slug>`, `swarm.sh drop <slug> <reason>`**
Take a merged story or epic (or, with `drop`, an escalated story) off the board.
On a board in the repo it deletes the file in the board PR `finish-<slug>` (or `drop-<slug>`), never in the main checkout, and prints the `swarm.sh merge --board <url>` that lands it.
On a board outside the repo it deletes the file where it is.

**`swarm.sh hold <slug> <why>`**
Log that a conductor held a ready story back this wave, and why: what it clashes with (a story or PR) and the shared files, or the other reason.
The reasons:

- `not held:`
- closed this wave
- the give-up rule
- what it clashes with (a story or PR) and the shared files

It writes one `hold` line, target the slug, outcome `ok (<why>)`.
It dies, writing nothing, on:

- a slug that is not a ready story on the board
- one whose PR was closed unmerged (its last event is reconcile's reopen): that story is the lead's, and a `hold` line would drop the mark `unblock --startable` prints for it

The conductor runs it for each `startable:` story it does not start, other than a closed-unmerged one: at most once per wave for a story, and in a later wave only when the reason changed.

**`swarm.sh restart <slug>`**
Start a builder again when its pane is gone.
It runs on a ready story that has a worktree and whose builder herdr no longer lists, and it uses the same worktree, branch and tab.
If the builder's last Claude session left a resume command, and that session took its brief, restart reopens it and tells the builder to carry on.
A resume command moved to a new session by `/clear` reopens the new one.
If not, it starts a fresh builder on the last model, with a handover brief like a step-up's.
It refuses, and starts nothing, while herdr still lists the builder, and when the story:

- has a PR that merged or is set to auto-merge
- has a step-up waiting (run `swarm.sh step-up --resume <slug>` for that)
- has no worktree
- has a worktree with a git step left unfinished (a merge, rebase, cherry-pick or revert, or an `index.lock`) or one off `story/<slug>`
- is `kind: lead`, held or escalated
- is not ready

It holds the story's step-up lock while it runs: a second restart of the story is refused, and an automatic step-up of it is skipped.
A restart is refused, too, while an automatic step-up holds that lock.
Its reads of herdr's agent list and of the story's PRs each stop after `SWARM_RESTART_READ_WAIT` seconds (30 by default), and a read that fails or stops refuses the restart and lets the lock go.
When herdr sends the brief or the prompt to carry on but does not show the builder taking it up, restart reads the builder once more.
If that read does not show it either, restart fails without an ok line, keeps the pane, and says what to send the builder.
It logs `restart <slug> ok (...)`.
The story's `attempts:`, its review round and the build the step-up triggers count from stay as they were.
In `outcomes`, a resumed session is the same build row, and a fresh builder is a new row with the next attempt number, as for any new builder.

**`swarm.sh wait --lead`**
Wait until the lead's queue gains one of these, and print each new one:

- a story PR that conflicts with its base (`conflict: <slug> <PR URL>, exit: tell its builder to merge the base in`)
- a blocked story whose dependency it shares no touches with (`idle: <story> waits on <dep> but shares no touches part with it and needs nothing from it`)
- an epic that can start or has no plan running (`idle: epic <epic> can start, ...`, `idle: epic <epic> has no plan running, ...`), as `next` prints them (`wait --lead` takes no step of its own, so its epic lines include the one `next`'s `plan-epic` step names)
- a ready story with no build past `queue_minutes` (`idle: <story> is ready with no build, exit: <exit>`)
- a started story with no live agent (`no-agent: <slug>, exit: <exit>`)
- a PR whose review agent never started or went (`no-review: <slug> <PR URL>, exit: swarm.sh review-agent <slug> <PR URL>, or the fallback reviewer`; for a review-agent start cut short with tries left, it starts the next try itself and the line says `(started N of 3)` after the PR, [§ The lead](reference-lead.md#the-lead))
- an agent stuck on a prompt, a dialog, an expired login, an API error or manual mode (`prompt: <agent> (<kind>), exit: <exit>`)
- a green PR in review that waits on you
- a held, escalated or kept story
- a failed step-up (`step-up failed: <slug>, exit: swarm.sh step-up --resume <slug>`)
- a review agent's stop note no running conductor has (`stopped: <slug> (<the note>), exit: <exit>`)
- a story PR whose idle builder has sat 60 minutes on findings or a conflict (`stuck: <slug> <PR URL> (<findings|conflict> pending <N> min), exit: swarm.sh tell <slug> resume <file>`)
- a story PR reviewed, green and left unmerged past `queue_minutes` (`unmerged: <slug> <PR URL>, exit: swarm.sh merge --head <sha> <PR URL>`)
- a brief still unsent after its resend (`unsent brief: <stem>, exit: <exit>`)
- any other line [§ The lead](reference-lead.md#the-lead) lists

A PR `swarm.sh merge` held for a protected path is `merge: <slug> <PR URL> (held: changes <path>; exit: the user merges it)`.
One held because its merge of the base dropped base lines is `merge: <slug> <PR URL> (held: dropped base lines: <n>, first <file>: <text>; exit: the builder restores them in a commit of its own, or the user reads the PR's answer and merges by hand)`.
One whose check could not run is `merge: <slug> <PR URL> (held: dropped base lines unchecked: <why>; exit: the user checks the merge by hand and merges it, or runs swarm.sh merge again)`.

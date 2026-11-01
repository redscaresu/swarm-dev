# Reference: Merging and releases

Part of [the reference](reference.md), which lists every section and the file that holds it.

## Merging

With `merge = human` (the default) no agent merges unless an HLD grants `merge`: each agent starts unable to run
`gh pr merge`, its brief forbids every other route, and the plugin's merge guard (below) refuses the common ones. When a story's PR passes review, its
review agent runs `swarm.sh review <slug> --head <SHA> <PR URL>` on the head it reviewed; for an item no
review agent hands over (an epic, or a story with several PRs), the lead or a conductor runs
`swarm.sh review <slug> <PR URL>...`. Either sets the item `status: review` with its PRs on a
`prs:` line, and `next` lists it as awaiting your merge. For a story under `merge = human`, or one
that costs money, `review` also notes the story's running conductor that it is in review, a note
that ends with the `finish:` line once the epic has no agent work left (§ Building). When the stories left in an epic are all
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
closes it first, which counts nothing while the story is in review. It closes the story's review
agent, `review-<slug>`, too. When reconcile runs in that agent's own pane, as a `swarm.sh merge` run
there does, it retires the agent instead, under a `-done` name (`review-<slug>-done` for a short
slug), so the pane running the merge stays open; `swarm.sh tidy --yes` closes it later. Its session
is archived to `.swarm/sessions` when it is retired, so that copy stops at the merge. A review
agent that is working or waiting in another pane is left open, and reconcile says so: it may be
running its own merge, whose reconcile then retires it. After a PR closed unmerged, the
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
cannot read a PR in review, the item stays in review until a later reconcile pulls. A story whose
file a pull already took off the board before reconcile saw its PRs merge (you pulled by hand, or a
reconcile stopped after its pull) is finished after the pull in the same way: its builder and idle review agent closed (or the review agent retired, when reconcile runs in its pane),
its build cleared in the repo the deleted file named, and `reconcile <slug> ok (finished)` logged.
When its builder's pane cannot be closed, its build and state stay, and the next reconcile tries
again. One whose PRs did not all merge, such as a story a board PR dropped, only loses its state. On a board outside the repo it deletes the file of the item that merged.
Reconciles in one project run one at a time (merges through a merge queue run side by side): one
waits up to 300 seconds (`SWARM_RECONCILE_WAIT`) for `.swarm/reconcile.lock`, then stops naming it.
Direct merges (no merge queue) into one repo's base also run one at a time in a project, from the
check that the base has not moved through `gh pr merge` and its read back, so two review agents
that pass at once cannot both merge a head the other's merge left untested. A merge waits up to 900
seconds (`SWARM_MERGE_LOCK_WAIT`) for `.swarm/merge-<owner>-<repo>-<base>.lock`, then stops naming the
pid that holds it. A lock whose pid is gone, or that has no pid file 10 seconds after it was made, was
left by a merge that died: merge takes it over and says so, one merge at a time. A merge that has
GitHub merge a moved base into its PR frees the lock while it waits for the new head's CI, and takes
it again before it checks the base once more (§ Merging, Waiting for the new head). `swarm.sh unblock` then readies a
blocked story once every slug in its `depends_on` is finished. It leaves an old `blocked_by` line as it is, since nothing reads it. With `merge = agent` each story's review agent merges that story's PR instead, only through `swarm.sh merge`, except for a story with `costs: money`: `swarm.sh merge` holds a PR whose story, or a story it stacks on, has `costs: money` or any other value but `none` for you, on every route (`held: <slug> costs money`). A `costs:` of `none` or empty merges, and an unreadable board story holds every PR (it fails closed). When another merge deletes a story file after `swarm.sh merge` listed the board, `merge` lists the board again, once, and reads it again. If a story file on that second list is gone by its read too, or a file is there but unreadable, the PR is still held, and a review agent merging its own story's PR is refused in the same cases. `swarm.sh merge` also holds a story PR that changes `.claude/`, `.github/`, `hooks/` or a root `Makefile`, `GNUmakefile` or `makefile`, in any case of letters, a renamed or removed file's old path included (`held: <slug> changes <path>, which only the user merges; the user merges it`). It does so after the story lookup and the head's CI check, reading the PR's files at the head it pinned, from GitHub's compare of the base with that head, so a later push cannot hide one (the review agent sends its conductor a stop note on either hold, and the conductor closes the builder); a transient gh error is read again, three reads in all, and the read stops after 60 seconds (`BASE_MOVED_WAIT`). When it still cannot read them, it holds the PR and says why. A hold from a passing error (three 5xx in a row, a read past the bound, a file count GitHub briefly reports wrong) clears on the next `swarm.sh merge`, so run it again; a PR of over 300 files (the most the compare lists) or of no file is never readable, so that hold stands. `--board` and `--release` PRs cannot change those paths. Nothing else lifts a protected-path hold for one PR: you merge it by hand, and the next reconcile finishes the story. `swarm.sh merge` records either hold on the item in review, as `protected: <PR URL> <head> <time> <path>` (or `unreadable: <why>` in place of the path) in its board-state file, and drops it when a later `swarm.sh merge` of that PR finds no protected path. `status` and `wait --lead` read the record with no gh call. They leave it out once a `wait --lead` heads pass made after the hold read the PR at another head (`.swarm/lead/held`); with no such pass, as when no `wait --lead` runs, the hold stands. A held PR's review agent leaves it for your merge. The conductor merges no story PR: the story's review agent does, and the lead may. Every agent, the conductor included, still starts unable to run `gh pr merge`. The head a review passed is the `head:` line of the
story's findings file. The review agent runs `swarm.sh review <slug> --head <that SHA> <PR URL>`, then
`swarm.sh merge --head <that SHA> <PR URL>`, which merges by the literal PR number
with `--match-head-commit` (with `--auto` only to enqueue it on a base with a merge queue), waits for CI on the base, and runs `swarm.sh reconcile`.
Both refuse a head pushed since the review. Reconcile pulls the board the way it does for you, and finishes
the story, closing its builder. Nobody closes the builder before that, because closing
a story that is still `ready` counts a failed build. Each review agent merges as soon as its own
review passes, so on a base with a merge queue the queue tests the PRs together and merges them in
batches. Otherwise each `swarm.sh merge` waits for any other merge into the same repo and base in
this project to finish first. A note in the conductor's inbox says each story PR that merged
(`swarm.sh merge` sends it). After each wait, once it has
read its inbox, the conductor runs `swarm.sh unblock --startable <epic>` (`--backlog` for the backlog conductor) and,
in the same run, starts each story printed as `startable:` that clashes with no running one (§
Building, Pick the wave). `--startable` runs unblock, then prints `startable: <slug>` for every `ready` story in that
scope with no worktree yet, whether or not this unblock readied it. A story that a board PR adds
already `ready` starts the same way. It reads the board as reconcile last left it and never pulls:
pulling is reconcile's job, which `swarm.sh merge` runs. A line ends `(stacked on <parents>)` while
the story's `depends_on` has open stories, and `(its PR <url> was closed unmerged)` when reconcile
last sent it back to ready; the conductor leaves that one for the lead. A build cleared on error or given up on stops that: it starts nothing more in
the wave. Once the epic's file is gone (its last story's PR deletes it), `--startable` still runs unblock
but lists nothing. The
conductor skips a story it closed in this wave (it may start it again in a later one), one its give-up rule says not to start again, and one
a `not held:` line left `ready` for the lead. If the last inbox pass before its report reads a note,
it runs `--startable` once more, and if that starts a builder, it goes back to waiting instead of
reporting. It never writes its report while agent work is left: a story of the epic, of a kind an
agent builds, that is ready (to start, building, or with its PR open and not yet in review), blocked
on an agent's work, or in review with its review agent still to act on it (a story a close kept with
one PR, or one its review agent merges next, under `merge = agent` or a `merge` grant, unless it costs
money or `swarm.sh merge` has handed it to you or the lead since its last review, as `events.tsv`
records: a hold, an unconfirmed merge, the epic guard), or a
fix-main story it started (the `story` line in `events.tsv` names its pane), which no other conductor
counts. A story reconcile reopened after its PR closed unmerged is the lead's. A story blocked only on
a `kind: lead` story or a hand step, blocked by hand with no `depends_on`, blocked only on stories that
wait on you that way, or in a `depends_on` cycle, waits on you: it holds nothing up, and the report lists it under
Waits on the user. Neither does a story the brief has the conductor list for the lead: a build that
died, a `not held:` line, a PR closed unmerged, or a kept story with several PRs. The note after the last such story's merge or handover ends `finish: epic <epic> has no agent
work left` (§ Merging); the conductor then closes each idle `review-<slug>` of its own still open,
with `swarm.sh close review-<slug>`, and writes its report. A working one is still handing its PR on,
so it is left for reconcile or `tidy` to close. With no such note it judges by the same rule.
A report written while a review agent still owned a PR would leave that PR's escalations with nobody,
since `next` collects a conductor on its report alone. Under `merge = agent` it also stops when CI
on the base timed out, or is red with no `fix-main:` line, saying so in its report.
It also stops when what is left needs the lead: a story only the lead can finish. If
CI on the base goes red, `swarm.sh merge` prints `fix-main:` and writes the fix-main story (below),
which `next` names to the lead first; the lead's note asks the conductor to start its builder at
once, ahead of every other story and whatever its scope, under either merge setting. `watch` says no
fix-main PR opened, so the conductor starts that PR's review agent once the builder replies with its
URL. A merge that `swarm.sh merge` refused or could not confirm, other than `held:`, a `base merged:`
line or a moved base (below), ends the review agent with the line in its reply and in a stop note to
its conductor, which nudges the builder on a dequeue and reports the rest for the lead. The lead merges
with `swarm.sh merge`: a one-off story with `merge = agent`. Under `merge = human` it merges a story
PR or board PR only when the agreed HLD over it lists `merge` in its `grants:` (the HLD
`swarm.sh grants <PR URL>` prints). It reads that grant once the PR's head is green. With the grant,
the `costs:` hold of `merge = agent` applies too, so a `costs: money` story's PR, and a board PR that changes a
`costs:` line, still wait for you; the protected-path hold is `merge = agent`'s alone, since under
`merge = human` the grant lookup already refuses a PR that touches one of those paths, the names as written. Without it, `merge` refuses with
`<PR URL> waits on the user's merge (merge = human, and no HLD grants merge for it)`. When a board
story, the PR's files, or its head or base cannot be read, so the HLD over it is unknown, it refuses with
`cannot tell which HLD <PR URL> is under, so it waits on the user's merge`. `merge` reads the grant,
and the PR's files, at the head and base branch it pinned. When the PR's head has moved off it,
`merge` refuses with `the head of <PR URL> is <sha>, not <pinned sha>, so no grant covers it: review
the new head`, and when the PR has been retargeted, with `the base of <PR URL> is <branch>, not
<pinned branch>, so no grant covers it: review it against <branch>`. GitHub lists 300 files at most
at a given head, so a PR that changes more gets `cannot tell which HLD`. When the HLD's `grants:`
holds a value swarm.sh does not know, or is not a one-line `[..]` list, it prints the line naming the
HLD's file and line, then refuses with
`the grants: of <HLD file> cannot be read, so <PR URL> waits on the user's merge`. Under `merge = human`,
`--release` merges only when the release is covered: at least one story file was deleted by the
base's own commits since origin's tag `v<base version>` (a merge commit's deletions count against
its first parent), and every such story, read as it was just before the commit that deleted it,
falls under an agreed HLD that lists `release`. It reads the board from the base on origin, since
your checkout may not have pulled. The story's epics are read as they were then, except that the
base's copy wins where it still has one. Its HLD comes from the base alone, so deleting an HLD, or
taking a grant off one, stops it counting once that change is on the base. A
story the base's board still holds, marked `done` in your board state because its PR left the file
in place, must fall under such
an HLD too when a PR from its `story/<slug>` branch merged since the tag, and then counts as a story
merged, or when gh cannot list those PRs, and then does not. Otherwise it refuses with `<PR URL> waits on
the user's merge (merge = human, and story <slug>, merged since v<version>, is under no agreed HLD
that grants release)`, naming the
first story it found uncovered. A board outside the project's repo never covers a release. A
covered release still goes through the docs check below.

`swarm.sh merge [--board|--release] [--head <sha>] <PR URL>` merges one PR. It refuses, merging nothing,
unless the PR is open, its head is `<sha>` when `--head` names one, and a story or epic in `review`
lists the URL on its `prs:` line. With `--board`, for a board-only PR, the PR must be in the
board's own repo (its origin) and every path it changes, a renamed file's old path too, must be
under the board instead. Under either merge mode, it also refuses a story PR or a `--board` PR that
sets an epic `active` with no ticket, as `board-pr open` does (§ The lead), or before the base allows
its stage ([§ Writing an epic](reference-planning.md#writing-an-epic), Staged epics). Once the head is green,
it reads each epic and HLD through gh at the PR's base branch and head SHA; for a story PR it first
lists the PR's files at that head. A renamed epic is read at its old path on the base (GitHub's
`previous_filename`), as `board-pr open` reads it: its `agreed:` is compared under any heading, its `active` carries over only while the heading is the same; the epic guard's list of the PR's files (`merge_files`) is read once per merge, within `BASE_MOVED_WAIT`, and read again only after a transient gh error, as the pinned list is. Any read error refuses, as does a 404 at the head on a file the PR
does not remove or rename away. For a story PR each of those reads, the file list included, stops after
60 seconds (`BASE_MOVED_WAIT`) and refuses the same way. For a `--board` PR the epic and HLD reads and the
epic guard's file list stop there; the path list `--board` checks first has no limit. A read cut off that
way is a passing error, which the next `swarm.sh merge` reads past. The refusal starts `--board:` only on the `--board` route. A story
PR is not checked when the board is not in the project's repo. Nor is one whose story names another
repo (`repo:`) and whose PR is outside the board's repo, since its `epics/` files are that repo's own;
when gh cannot name the board's repo, merge refuses, says why, and you run it again; when the project
has no origin remote, it says to add one, or to merge the PR by hand, since running it again fails the
same way. Under
`merge = human`, a story PR whose files cannot be read at the head waits on your merge. With
`--release`, for a release PR, the PR must be in the project's own
repo and go into its base, and it may change only `"version"` in `.claude-plugin/plugin.json`, since
hooks, MCP servers and command paths there run code. The new version must be MAJOR.MINOR.PATCH and
greater than the base's. When `bin/`, `commands/` or `hooks/` changed between the tag
`v<base version>` and the base but README.md, AGENTS.md and `docs/` did not, it refuses and names
the changed paths, unless the PR body has a `Docs: none — <reason>` line. That line may be a `- `
or `* ` list item and may use `-` or `--` for the dash. The reason must be at least two characters,
and a placeholder such as `<reason>` does not count, nor does a line inside a ```` ``` ```` fence or
a `>` quote. A change to `commands/*.md` is the text a user reads, so it covers itself when nothing
else in the code changed; next to a `bin/` or `hooks/` change it does not. The board's own paths
(`stories/`, `epics/`, `hld/`, `Board.base`, `.obsidian/`) are not docs, even when the board is
`docs/`; the rest of `docs/` is. It compares against origin's tag by its SHA and never fetches
over your local tag. It refuses when origin has no
such tag or the tag is not on the base. No story or epic need list it. These checks all read one
commit of the base: `--release` fetches the base from origin first and remembers what it got. Right
before `gh pr merge` it fetches the base again. If the base moved, it prints `origin/<base> moved
from <old> to <new> since the release check, so it runs again`, runs every `--release` check again
on the new base, and refuses if one fails. A story that landed in between under no HLD granting
`release` is refused like any other.
The head must be green: at least one check run, every run
completed as success, skipped or neutral, and every commit status a success. Merge does not check
which workflows should have run, so a direct `swarm.sh merge` on a head with one fast green check
still merges. `swarm.sh wait-pr` does, and the swarm's procedure (`commands/swarm.md`) runs it before
each merge. In wait-pr, an expected workflow that has not started counts as pending. It reads every page,
and any gh error or answer it cannot read is a refusal. It merges with the repo's method (squash
when allowed, else a merge commit, else rebase) and `--match-head-commit`, so a head that moved
after the check stops the merge. It never passes `--auto`, except to join a merge queue (below). It passes `--admin` only with `merge_admin = on`, and only after `ci_gate admin` passes (§ Settings).

**Held for dropped base lines.** A builder that merges the base into its branch and resolves a
conflict can drop a line the base had, and neither CI nor the review may notice
([#693](https://github.com/redscaresu/swarm-dev/issues/693)). Under either merge mode, `merge` checks a
story PR or a `--board` PR at the head it pinned, after the epic guard and before the HLD grant. It
first lists the PR's commits through gh, every page, within 60 seconds (`BASE_MOVED_WAIT`). When the
list holds that head and none of them is a merge commit, there is nothing to check. A list that lacks
the head belongs to another head or is stale. When the PR now has another head, `merge` goes on, and
its pinned `gh pr merge` refuses that head; otherwise the PR is held, unchecked. When the list holds a merge commit,
`merge` runs `swarm.sh dropped-lines` on that head (§ Commands). When that prints lines, `merge` holds the PR for you, with the count and the first
line: `held: <slug> (dropped base lines: <n>, first <file>: <text>); the builder restores them in a
commit of its own, or the user reads the PR's answer and merges by hand`. When the check cannot run, it
holds the PR too and says why: `held: <slug> (dropped base lines unchecked: <why>); the user checks the
merge by hand and merges it, or runs swarm.sh merge again`. That covers a gh or fetch error,
git below 2.36, a merge the scan cannot read (an octopus, or a stacked build's merge of its parent
branch), and a PR with 250 or more commits, the most GitHub lists. A passing error clears on the next
`swarm.sh merge`. When the PR's head moved on GitHub meanwhile (`refs/pull/<n>/head` is another commit,
or gh no longer lists the head), `merge` refuses for a new review instead, with a line that ends
`review the new head`. On a `--board` PR the held line names the PR's URL in place of a slug, and
nothing is recorded. On a story PR either hold is recorded on the item in review, as a protected-path
hold is: `protected: <PR URL> <head> <time> dropped base lines: ...`, with each `|` written as `¦`,
since the record separates its entries with ` | `. A later `swarm.sh merge` that finds nothing dropped
removes the record. `--release` reads no commits, since a release PR changes only `plugin.json`. A
commit that puts a dropped line back does not clear the hold: the scan reads each merge as it was made.
Only a branch rebuilt without that merge, or your merge by hand, ends it.

**A base that moved.** A PR's CI ran against its base as the base was then. Two PRs can each pass
alone and break the base together: in v0.28.0, #527 and #530 each passed CI before #529 landed, and
main went red. So, on the direct path, a story PR's `merge` compares the head with the base
(`compare <head>...<base>`) once the head is green, just before `gh pr merge`. The direct path is
every merge that does not join a merge queue: a base with no queue, and every merge under
`merge_admin = on`, which never reads whether the base has one. When the base has
commits the head lacks and any of them changes a path off the board, `merge` does not merge that
head. It has GitHub merge the base into the PR's branch, waits for the new head's CI and merges the new
head instead (Merging the base in, and Waiting for the new head, below). The board's paths are `board_paths`' entries, which the board-only CI gate from `swarm.sh
init` skips: `stories/`, `epics/`, `hld/`, `Board.base` and `.obsidian/` under the board, and only in
the board's own repo. Commits that change only those run no tests there, so they do not count. A
`README.md` there counts as code, since a test may check it: swarm-dev's own CI gate tests the board
READMEs. When the base gained only board paths and the board's repo cannot be read (no origin, or gh
cannot tell which GitHub repo it is), `merge` refuses naming that read, with gh's own error line.
That refusal also ends `merge origin/<base> in, push, and merge the new head`: once the head has the
base, there is nothing to read. A compare it cannot read
refuses too, and so does one listing 300 files or more, since GitHub lists no more, or one that lists
no file for the commits (a commit and its revert give no file). The 300-file and no-file refusals end
`merge origin/<base> in, push, and merge the new head` as well, since merging the base in clears them, and the conductor
handles them as it does the moved-base refusal. A transient gh error (a 5xx, a rate limit, a timeout)
is read again, three reads in all; any other read error refuses at once. Each read, the compare's
retries included, stops after 60 seconds and refuses naming the wait. The check is cautious on purpose. GitHub ran the PR's CI
on a merge ref, which may already hold some of those commits, and the price is one more CI run.
Nothing locks the compare against the `gh pr merge` that lands the PR. Two merges into one base, such
as two epics' conductors, can both read the base as unchanged and both land seconds apart. Only a
merge queue closes that window. `--board` and `--release` skip the check. A PR that joins a merge
queue skips it too, since the queue tests each PR on top of the base. Under `merge_admin = on` no PR
joins one, so the check runs on every story merge.
Under `merge_admin = on`, a base that requires PRs to be up to date is still `ci_gate admin`'s to
refuse.

**Merging the base in.** For a PR whose base moved, `merge` sends `PUT
repos/<owner>/<repo>/pulls/<n>/update-branch` with `expected_head_sha` set to the head it read, so
GitHub refuses if the branch moved since. GitHub merges in the background, so `merge` then reads the
PR's head up to 20 times, 3 seconds apart (`MERGE_UPDATE_READS`, `MERGE_READ_WAIT`), until it moves.
It accepts the new head only when GitHub made it, its first parent is the old head, its second is a
commit on the base (the base's head, or a commit behind it: `compare <parent>...<base's head>` says
`ahead` or `identical`), and every file it changes is that commit's own version of a file the PR
left alone. Then the only new content is the base's, and nothing of the PR's is lost. GitHub made it when its committer is `web-flow` and its signature is verified, as on GitHub's
own merges. A builder's own merge of the base, pushed while GitHub's was pending, has the same parents
but may hold more. A pusher can name `web-flow` as the committer, but cannot sign as GitHub. What it
changes is checked too, since a conflict resolved in GitHub's web editor is also a verified `web-flow`
merge of those two parents. `compare <old>...<new>` must list the same files as `compare
<old>...<second parent>`, each with the same status, old path and blob, and none of them may be a
file `compare <second parent>...<old>` lists, the PR's own changes. So a file the PR changed too is
refused for review, even when GitHub merged it cleanly. Matching patch lines would pass a base change
made at another place, and a matching blob alone would pass a resolution that dropped the PR's edit
for the base's version. A list of 300 files or more refuses too, since GitHub lists no more. It logs `merge <slug> base-merged <new head> from <old head>`
in events.tsv, so later steps can tell this head from a builder's push, and prints `base merged:
<PR URL> is now <new> (<old> with <base> merged in); waiting up to <seconds>s for its CI`. Each of its
reads stops after 60 seconds (`BASE_MOVED_WAIT`), as the compare's does. Before it has a new head it
refuses, naming the cause, in five cases. The first four end in `merge origin/<base> in, push, and
merge the new head`, as the moved-base refusals do:

- GitHub answers 422 and the head has not moved, a conflict: `the base <base> moved past <sha>'s CI
  (<n> commits it lacks), and GitHub cannot merge it in, a conflict (HTTP 422: <GitHub's message>):
  merge origin/<base> in, push, and merge the new head`. GitHub also answers 422 when the head has
  moved since `merge` read it, so `merge` reads the head again. When it has moved, that head goes
  through the checks above: a builder's push is a new head to review, and GitHub's own merge of the
  base is accepted. When gh cannot read it again, `merge` refuses naming the 422 and says to pull the
  branch first.
- The request fails another way: `..., and asking GitHub to merge it in failed (<error>): ...`.
- GitHub does not answer the request within 60 seconds: `..., and GitHub did not answer the
  request to merge it in within 60s: pull the branch first (GitHub may yet push its merge), then
  ...`.
- The head has not moved by the last read: `...; GitHub took the request to merge it in, but its head
  was still <sha> after 20 reads 3 s apart: pull the branch first (GitHub may yet push its merge), then
  ...`.
- GitHub did not make the new head, it has other parents (a builder pushed at the same moment, say),
  a file it changes is one the PR changed too or is not the base's version, or gh cannot read its
  parents, the base's head or the compares: `base merge unchecked: <PR URL>'s head moved from <old> to <new>, <why>: review the new
  head as for any new head`.

From the second round on, and for a head an earlier `merge` run made (its `base-merged` line in
events.tsv), the PR's branch holds GitHub's merge, which the builder's worktree lacks. So the first four
say `pull the branch first (it holds GitHub's merge <head>), then merge origin/<base> in, push, and
merge the new head`, and the base check's own refusals, with a compare that fails, say the builder
pulls its branch first too.

**Waiting for the new head.** Once it has a new head, `merge` waits for that head's CI itself, with
`swarm.sh wait-pr`'s own loop: every 20 seconds (`MERGE_POLL`), for up to 30 minutes
(`MERGE_CI_SECONDS`), it reads the head's check runs and commit statuses, and the runs of each workflow
that a pull request into the base runs with the PR's files. A spent rate limit is waited out to its
reset, and a conflict with the base ends the wait, as in wait-pr. Its grace for no check runs, or for
an expected workflow with no run, is 60 seconds (`MERGE_CI_GRACE`) here, not wait-pr's 5 minutes. While
it merges the base in and waits, it frees the merge lock, so other merges into the base go on, and it
takes the lock again after the wait. A merge that cannot take it again within 15 minutes refuses,
naming the new head's `wait-pr --head` and `merge --head`.

Then it reads the PR again. If the PR merged during the wait, by another `swarm.sh merge` or by
hand, it prints `already merged: <PR URL> merged while this run waited on <head>, by another swarm.sh
merge or by hand; reconciling`, logs `merge merged elsewhere` and merges nothing. It skips its own
`merge ok` and its wait for CI on the base, and runs `swarm.sh reconcile`, since a merge by hand has
no other run to do it; after another run's reconcile it finds nothing left. Then it notes the story's
running conductor that the PR merged, as after any merge, naming a reconcile that failed. The note
also says this run did not wait for CI on the base, which after a merge by hand nothing does, so the
conductor starts no story that waits on this one until CI on the base is green. A PR closed meanwhile
refuses. A head an earlier `merge` run made by merging the base in (its `base-merged` line) gets the
same wait before its base check, so a run of `merge --head` on it waits on the workflows too, which
the plain check on the head does not read. A head that moved (a push during the wait) refuses as `base
merged, head moved:`, for a review of the new head. Otherwise it compares the head with the base
again, right before `gh pr merge`. If the base gained more code during the wait, `merge` merges it in
again and waits again, for 3 rounds at most (`MERGE_BASE_ROUNDS`). If the base has moved again after
the third, it refuses. Under `merge_admin = on`, `ci_gate admin` then checks the new head as it
checked the old one, since `--admin` skips every rule on the base, and refuses with `--admin may not
merge <new head> into <base>: <why>` when it fails. Otherwise it merges with `--match-head-commit <new
head>` and goes on as for any merge, so events.tsv shows each `base-merged` line, then `merge ok`. A
merge whose base moved can therefore run up to 30 minutes longer for each round.

The wait refuses, merging nothing, as `base merged, <cause>:`, naming wait-pr's reason:

- `red`: a check on the new head failed. The refusal names the red checks.
- `no check runs`: the new head still has no check run 60 seconds after the first read that found none.
- `no workflow run`: a workflow a pull request into the base runs has no run on the new head 60
  seconds after the first read that found it missing. The PR's merge ref follows the base, so a
  workflow the base gained after GitHub made the head is expected there though it never runs on it.
  So when the base has moved since, `merge` merges it in again, a new round, instead of refusing.
- `timed out`: the new head is still pending after 30 minutes, or a rate limit resets past the
  deadline. The refusal names what is pending.
- `unread`: gh failed to read its CI, past wait-pr's retries.
- `conflict`: the new head conflicts with the base. The refusal ends `pull the branch first (it holds
  GitHub's merge <new head>), then merge origin/<base> in, push, and merge the new head`, as the
  moved-base refusals do.
- `head moved`: the PR's head moved during the wait, a push. Its red, if it had one, is the old
  head's, so this cause wins over `red`. The refusal says to review the new head as for any new head.
- `still moving`: the base gained more code after the third round.

Each but `conflict` says the builder pulls its branch (`git pull --ff-only`) before it pushes, since
GitHub's merge commit is on the PR's branch but not in the builder's worktree. All but `red`,
`conflict` and `head moved` also name the next step, `wait-pr --head <new head> <PR URL>, then merge
--head <new head> <PR URL>`, which for a base still moving waits until the base is quiet.

A head that merge made this way is not new work. `swarm.sh watch` reads the `base-merged` lines in
events.tsv. For a head one of them names, it prints no `checks finished on <sha>` line and no `opened`
line, so no review starts for it, and it leaves the head out of the ladder's red heads, as a review
pane's `wait-pr` does. It still reads the PR's mergeable state, and says when that head conflicts with
its base. A builder's later push is a new head, and watch reports it as before. The review checks
count a `base-merged <head> from <old head>` head as reviewed when `<old head>` passed review (each
link followed, 10 at most): `queued:` lines, the lead's `unmerged:` line and a give-up's `kept:` note
all read it so. So a reviewed PR whose merge stopped on such a head still comes back to the lead as
`unmerged:` once `queue_minutes` pass.

Two `swarm.sh merge` runs of one PR at once (a review agent's and the lead's, say) both read the same head
and both ask GitHub to merge the base in. If GitHub takes both requests, each run reads the head until
it moves. If GitHub answers the second with a 422 because the first merge has moved the head, the
second run reads the head again. Either way, each run puts the head it reads through the same checks.
A head that is GitHub's merge of the old head and the base passes them, so both runs print the same
`base merged:` line and wait on that head, and events.tsv gets two `base-merged` lines for it. Any
other head is a new head to review.

Each of these lines goes to whoever ran `swarm.sh merge`, with the step to take in its message. Under
`merge = agent` or a `merge` grant that is the story's review agent, never a conductor. On `base
merged:`, the new head needs no new review, since its only new content is the base's: `merge` waits
for its CI and merges it, and the review agent leaves it to finish; on `already merged:` merge has
reconciled, and nothing is left to do. On `base merged, red:` or `base merged, conflict:`, and on a
refusal that ends `merge origin/<base> in, push, and merge the new head`, the review agent nudges the
builder, naming the red check or the base to merge in, and telling it to pull its branch first with
`git pull --ff-only origin story/<slug>` (GitHub's merge commit is not in its worktree), then stops.
The pull names the branch, since a story's worktree tracks origin/<base>, and a stacked story's
tracks nothing. It sends its conductor the same stop note as for any other refusal, and the
conductor starts a new review agent on the head the builder pushes once `watch` reports its checks
finished, so that head is reviewed before it merges. A `base merged, head moved:`
refusal is a moved head: the review agent stops with `head moved:`, and the new head is reviewed the
same way. Any other refusal, another `base merged, <cause>:` or a merge lock it could not take again
included, ends the review agent with the line in its reply and in a stop note to its conductor, which
acts on a dequeue and reports the rest for the lead; with no conductor running, the lead acts on it. On `base merge unchecked:`, the new head is reviewed as any new head, the same way. That
head may be a builder's push, a merge made by hand, or GitHub's own merge of the base that touches a
file the PR changed too. When that review sends findings, the builder pulls its branch first, since
a merge commit on the branch is not in its worktree and its push would be refused.

**init's Claude Code checks.** An agent's `swarm.sh merge` runs only when a `permissions.allow`
rule in Claude Code's settings allows it. Without one, under `merge = agent` or an HLD that grants
`merge`, Claude Code refuses every `swarm.sh merge` an agent runs. In v0.28.0 that left 8 approved
PRs for the user to merge by hand. `swarm.sh init` reads `permissions.allow` in three files: your
settings (`settings.json` under `CLAUDE_CONFIG_DIR`, or `~/.claude/settings.json`), and the
project's `.claude/settings.json` and `.claude/settings.local.json`. It pools their rules and checks
every form an agent runs, on two PR numbers and head SHAs of the project's GitHub origin, so a rule
tied to one PR or SHA does not count: a conductor's
`swarm.sh merge --head <sha> <PR URL>` and `swarm.sh merge --board <PR URL>`, and the lead's
`swarm.sh merge --release --head <sha> <PR URL>` and `swarm.sh merge <PR URL>`. One rule that covers
them all is `Bash(swarm.sh merge *)`, the older `Bash(swarm.sh merge:*)`, or a wider one such as
`Bash(swarm.sh *)`. `Bash` alone and `Bash(*)` do not count: agents run in auto mode, which sets
such broad rules aside. When the rules miss a form, init names the files it read and prints your
step: add `"Bash(swarm.sh merge *)"` to `permissions.allow` in your settings file, which it names. A
file that is missing or is not JSON counts as having no rule. init reads only these allow lists, so
a deny or ask rule, or managed settings, can still block a merge it found allowed. It reads nothing
else in these files, since they can hold tokens under `env`, and it never writes them or
`~/.claude.json`.

init also checks that auto mode has learned your environment. In v0.28.0 the 'Teach auto mode'
dialog and auto mode's permission prompts left at least six builder panes stuck for hours. Claude
Code's `/auto-mode-setup` reads the project and your recent sessions and writes a list of
`autoMode.environment` entries to your settings file. Claude Code offers the dialog only while that
list is empty. It merges the list from your settings, settings passed with `--settings` and managed
policy settings, and ignores `autoMode` in a project's settings files. init reads only your settings
file, and only that list. When the list there is empty or missing, init prints your step: run
`/auto-mode-setup` once in `claude`, then `swarm.sh init --auto-mode-done` from the project's root.
If your organisation sets the list in managed settings, you never see the dialog, so just run
`swarm.sh init --auto-mode-done`. That command writes today's date to `.swarm/auto-mode-done`, and
its own line to `.swarm/events.tsv`, and nothing outside `.swarm/`. It does not set the project up.
Once that file exists, or once your settings have the list, init no longer prints the step.

**The conduct preflight.** Under `merge = agent`, no conductor starts while the three settings files
init reads lack the `swarm.sh merge` rules it checks for, since Claude Code would refuse every merge
the conductor's review agents run. `swarm.sh conduct` (an epic's or `--backlog`) exits 1 with this line before it writes a
brief or opens a workspace or tab: `no conductor started: merge = agent and no allow rule for
swarm.sh merge in <files read>; add "Bash(swarm.sh merge *)" to permissions.allow in one of them
(swarm.sh init checks it)`. While `swarm.sh next` waits on a working conductor, it starts none for
other ready work, logs no `conduct` line, and prints the same line once, however many epics wait.
With no conductor working, `next` names the `conduct` (or `story`) step, and the line comes from the
`swarm.sh conduct` that step runs. The line names every file it read, so a rule written in a form
swarm.sh does not read (a full path to `swarm.sh`, say) still shows why no conductor starts. Under
`merge = human` nothing is checked.

**Merge queue.** With `merge_admin` off, `merge` asks GitHub whether the base has a merge queue
(GraphQL `repository.mergeQueue(branch:)`, which covers a ruleset's `merge_queue` rule and classic
branch protection alike) before it merges. When it has one, `merge` enqueues the head with
`gh pr merge --auto --match-head-commit <head>` (the queue picks the method) instead of merging.
The queue tests the PR on top of the base and the PRs queued ahead of it, so two PRs that are each
green alone but red together never land. `merge` reads the PR back even when gh fails, since an
error can follow an enqueue GitHub made, and a PR already in the queue is waited on as if it had
just joined it. It prints `merge queue: <base> has one` first, whatever happens next. Then it reads
the PR every 20 seconds until it merges or leaves the queue, and checks its head on every read. The
30 minutes for CI start when the PR's own merge group starts, and again for each group the queue
rebuilds; waiting its turn behind other PRs, or for auto-merge to enqueue it, has a bound of its own,
six times that (3 hours), which starts again when the queue takes its group apart. A head other than the one it checked stops the wait:
`merge` turns auto-merge off and takes the PR out of the queue (GraphQL
`disablePullRequestAutoMerge` and `dequeuePullRequest`), so a push made before the PR reached the
queue never merges unreviewed. If the PR has already merged at another head, `merge` logs
`merge merged at head <sha>, not <sha>, ...`, runs reconcile (main has changed) and exits non-zero,
so the merged code gets a review. A merged PR logs `merge ok`, and a
`main-ci` wait follows before reconcile, as for a direct merge: the queue ran the PR's checks on its group, but the
workflows that run only on a push to the base (a release, a deploy) run where the base was pushed.
The queue pushes a batch of PRs at its last commit, so `merge` waits on the base's head once it holds
the PR's merge commit, not on that commit itself. A PR that reads merged
before GitHub shows its merge commit is read again, up to three times. A PR that leaves the queue
unmerged is a dequeue when GitHub logged its removal after this enqueue (one dropped within seconds
for a conflict counts, an earlier run's does not), even while its auto-merge still reads on, which
`merge` then turns off; or when three reads in a row, after one showed it
queued or waiting for auto-merge, find it out of the queue and not merged. `merge` exits non-zero with one
`merge dequeued (<GitHub's reason>): <checks>` line naming the checks that were red or unfinished on
the merge group's commit. That commit is the one seen while the PR was queued, or, for a PR that
joined and left between two reads, the one its `merge_group` run names; the reason is GitHub's only
for a removal after this enqueue. The review agent that ran `merge` sends its conductor a stop note
naming the dequeue (`review-<slug> stopped on <sha>: ...`), and the conductor handles it like a red
check: it nudges the builder with the failing checks, the builder merges the base in and pushes, and
the new head gets a review agent of its own, which merges it once it passes. A wait that runs out or errors, a PR that never reads as queued, and a TERM, HUP or INT
while `merge` enqueues or waits each turn auto-merge off and take the PR out of the queue. Each is logged as
unconfirmed (`stopped by SIGTERM` for a signal), naming anything it could not undo for you to do by
hand; running `merge` again enqueues it again. A PR that never reads as queued after gh failed on
the enqueue is a refusal instead. If the queue cannot be read (three tries), `merge` refuses and merges nothing: on a
base with a queue, a direct merge would enqueue the PR with nothing watching its head. `--release`
never joins the queue, where a PR queued behind it could share its push and so its tag, and a base
that requires a queue takes no direct merge but `--admin`'s, which `merge_admin = off` rules out. So
`merge --release` refuses there, naming the queue, and the release is yours to merge once the queue
is empty. With no
queue the path is the one above. ci.yml and zizmor.yml run on
`merge_group`, and ci.yml's gate reads the base's copy of board-only.sh from the merge group's base,
so the required checks report on each group. infrafactory keeps no queue: its ruleset needs an approving review, and `merge_admin = on`
merges with `--admin`, which would skip a queue. `ci_gate admin` refuses a base with a
`merge_queue` rule for that reason.

It reads the PR back after `gh pr merge`, whether gh succeeded or not, since an error can follow a
merge GitHub made. A PR that does not read as merged is read again a few times, then logged as
unconfirmed, for you to check by hand: it may well have merged. Only a failed `gh pr merge` on a PR
that still reads open or closed is a refusal. Then it waits up to 30 minutes for CI on the merge
commit, so run it in the background: each workflow whose `on: push` filters cover the base and the
files the PR changes must have a run on that commit, and every run and check there must pass. The
commit needs no check run of its own when no workflow is expected on it, but then it waits a minute
before calling main green, for checks other apps post just after the push. A failed read is a
missed poll, and three in a row end the wait as an error. When the base requires status checks (its
rulesets and branch protection, read once per merge, each check bound to the app the rule names),
only those can make main red. When any part of the rules cannot be read, merge prints `warning:
could not read <base>'s required checks (<why>), so every check counts`, and every check does. Any
other red check or workflow run waits until each required check has a run on the merge commit (a
workflow that never started holds main until the wait runs out, and the timeout names the required
checks with no run). Once every workflow expected on the push has finished, a required check still
with no run (a `pull_request`-only one, say) will never get one, so every check counts from then
on. Otherwise, once each required check has a run, a red that is not required prints `warning: <check> is red on <base>, which does not require it` and
leaves main green. Once every required check has finished green, nothing else is waited on. A
red whose every check is a GitHub Actions job gets one rerun per run: once those runs have
finished, merge reruns their failed jobs (`gh run rerun --failed`) and waits again, for the full
time. A red whose run, or rerun, is still going when the wait runs out is red. A transient gh error on the
rerun (a 5xx, a rate limit, a dropped connection) is a missed poll, and three in a row end the wait
as an error. If a rerun goes green, merge
prints `flaky: <jobs> (<the FAIL lines of the attempt that failed>), green on rerun` and logs a
`flake` line. If it goes red again, merge writes the fix-main story. A red that is not an Actions
job writes the story at once, and so does a rerun GitHub refuses. A `note:` line first among the
story's CI output, and among merge's, says that the rerun failed too, or why GitHub refused it, and
names any rerun still under way. `swarm.sh reconcile` clears a red main by the same rule: once each required check
has a run, only those must pass. Without
`--board` or `--release` it then runs `swarm.sh reconcile`, also after a red main, since the PR has merged.
For a story's PR it then sends the story's running conductor (the backlog conductor, for a story with
no epic) one note: the PR merged, and these stories of its epic are ready now. They are the blocked
stories whose `depends_on` names the merged story and has nothing open left, which the conductor's
`swarm.sh unblock` readies. It asks the conductor to start only those `unblock --startable` would
print, so a `kind: lead` story or one whose build is already there is left out. A held child review
among them is named apart: unblock readies it as held, so the conductor has its builder merge the
base in and starts its review agent again, and never starts a build for it.
When reconcile fails, when it leaves the story in review (it held the pull, or could not read the
PR), when CI on the base is not green (red, timed out or an error), or when the merge queue merged a
head nobody checked, the note says so in place of those stories. After a base that is not green, or
that queue merge, it also asks the conductor to start none of them, as a `--board` merge tells no
conductor on a red main. That note says it overrides the startable pass its wake prompt asks for:
reconcile has finished the story, so `unblock` would ready them. Merge still exits non-zero after each of these but a story left in review.
When the note names no such reason and the epic has no agent work left after the merge
(§ Building lists what counts), the note ends with a line `finish: epic <epic> has no agent work left`
(`finish: the backlog has no agent work left` for a story with no epic): the conductor's cue to close
the review agents it left and write its report. The handover note `swarm.sh review` sends ends the
same way. A fix-main story's handover note goes to the conductor that started it. Its merge note, with
the stories it made ready, goes to the backlog's conductor, and the conductor that started it gets one
that it merged, with no ready list. A `--board` merge's note never carries it.
A conductor that has written its report counts as not running; with none running, merge prints a
`ready now:` line for those stories instead, a held one marked `(held)`. Since the PR has merged
by then, each herdr call the note makes stops after `SWARM_NOTE_HERDR_WAIT` seconds (30 by
default). The conductor's pane is read from the note's one list of agents, so a herdr read that
fails after it is the note's warning, never a conductor taken for gone. A herdr that cannot list its
agents in that time, or gives a list that does not parse, or a note that fails, is a warning and
never fails the merge.
With `--board`, on a green main and when the main checkout has an upstream, it runs `swarm.sh
reconcile` too, which pulls the board. A story counts as newly ready when it was not buildable before the merge, is now,
has not started building, and has a file the board PR itself changes that wasn't buildable on the
board the PR merged onto (the first parent of the PR's own merge commit, even when a merge queue
pushed it with others; for a rebase merge, the commit below the PR's first) and is at that merge
commit, or an epic file that the PR changes for an epic that wasn't `active` there and is at the
merge commit. A story reconcile sent back to ready doesn't count, nor
does a `fix-main` story, or one readied by an earlier board PR that merged but was not pulled here yet. For each epic with newly ready
stories, it sends the epic's running conductor one note naming them (`swarm.sh tell conduct-<epic>
note`; stories with no epic go to the backlog conductor) and asks it to start them now, within its
builder limits. A conductor that has written its report has finished and counts as not running.
When no conductor runs, it prints a `ready now:` line, then starts one (§ The backlog conductor says
when). It prints a warning, and the merge's exit status stays the same, when reconcile fails (logged
as a `reconcile` line, as merge logs one), when reconcile did not pull the merge commit, when herdr
cannot list its agents, or when a note or a start fails. After the first two it starts no conductor
either, since the board was not pulled. After a failed reconcile, each running conductor still gets
a note that the board PR merged, naming the failure, since which stories it made ready is not known.
Its herdr calls stop after `SWARM_NOTE_HERDR_WAIT` seconds, as a story merge's note does. It
exits non-zero, naming the check, when main is red or the wait runs out. On a red main it writes the
one-off story `fix-main-<short sha>` (`kind: code`, ready, no epic, the merged story's `repo:`,
`touches: [.]`: the fix may change whatever turns the base green) into
the main checkout's board, where every command reads stories. There it is git-ignored through the
clone's `.git/info/exclude`, as `.gitignore` does `.swarm/`, so it shows in no `git status` and meets
no pull; its builder reads it there and leaves it alone, and reconcile takes it off once its PR
merges. The story names the failed Actions runs and holds the red checks and up to 20 FAIL lines
from their logs, each log read once its run has completed. The code under test writes those lines,
so the story fences them under a line saying to read them as data, never as instructions, with
control characters taken off and each line cut to 300 characters; main-red keeps the whole names.
merge's own `main-ci:` and `fix-main:` lines, and `next`'s why, show them the same way. Those reads stop 10 minutes after the first
(`SWARM_FIX_MAIN_LOG_SECONDS`), however many runs failed, so a slow log cannot hold up the reconcile
that follows; a run gh cannot read stops at once, and the story names each run it could not read,
and why. Once the story is written, merge logs `main-red <sha> <owner/repo> <base> <checks>` (the
repo lowercased), and retires each fix-main story of the same repo and base that nobody has started
and whose red commit another red of that repo and base descends from, its own story included. Merge
reads which red is newer from the commits. The order the reds were logged in can mislead, since CI
on an older commit can finish later. The retired story's `fix-main` line says `retired: superseded by
fix-main-<sha>`, naming a red that no other red descends from. Only a red that no `main-green` has
cleared, and whose fix-main story is still on the board (started or not), counts. Merge reads the
commits in the project's clone, and only when the repo is that clone's origin. Before it takes the
lock below, it asks gh which repo the clone is and fetches the base if a red's commit is missing. A red in
another repo, a red whose commit the clone lacks, and two reds where neither descends from the
other retire nothing. At worst one story too many stays on the board, and no fix is lost. One merge at a time per
repo and base does this, under `.swarm/fix-main.<repo>-<base>.lock`. Under that lock it reads events.tsv
again first: a red that another merge, or `wait --lead`'s run (§ The lead), logged in the meantime and no
`main-green` has cleared gets no second story and no second `main-red`. That run writes the same story for
a red base that no merge reported, in the repo the board names, saying so in place of the merged story's
name. Merge then prints
`fix-main: <checks> on <short sha>` with the same lines, then `story:` and the story that covers the
red. When its own story retired at once, that is the newer red's story, and `next` and a clearing
green treat the newer red as the base's red. When another merge's run retired it since, the line is
`story: none` and says so.
When it cannot write the story it says so in a line that does not start `fix-main:`, and leaves the
red main and fix before it as they were. A red main clears, logging `main-green` and retiring its
fix-main story if nobody has started it, only on a commit that shows it fixed and has the red
commit in its history (a merge that landed before it, its CI wait ending later, fixes nothing): a later merge into
the same repo and base, or the base's head that reconcile or `wait --lead`'s heads pass reads (a revert, a re-run), that changes
more than the board's own files (a board-only commit's CI may skip its tests, so a board-only head
is judged by the newest commit before it that is not), has every check, status and workflow run green (a commit with only statuses counts), and has a passing run of each
check that went red, or, when the base requires checks, of each of those (a fix may rename or drop the
failed job; a path filter may skip a check the base does not require). Until then, while the story is buildable (ready, `kind: code`: one escalated or held for the lead goes
to the lead's queue instead) with no build of it, `next` names
`fix-main fix-main-<short sha>` ahead of everything else, a conductor's wait included. Inside herdr it runs only
from a pane this project did not start (the lead's), from a conductor's with `merge = agent`, or
from `review-<slug>`'s for a PR on story `<slug>`'s `prs:` line, without `--board` or `--release`.
It refuses a pane it cannot identify. It takes a pane as `review-<slug>`'s only when every tab
record for the pane names `review-<slug>` (a retired `-done` name does not count), the newest
`.swarm/agents.tsv` line for that name has role `review`, and herdr's agent in the pane holds that
name, so a record left over after the agent exited or was retired is refused. The builder of a story slugged `review-x`
has a builder's role there, so it is refused. Under `merge = human` a review agent merges only where
the HLD grants `merge`, as the lead does.

`swarm.sh review <slug> <PR URL>...` sends the story's running conductor (the backlog conductor, for
a story with no epic) a note too, as a story merge does, when it puts a story in review with
`merge = human`, or a story with `costs: money` (or any `costs:` value but `none`) with
`merge = agent`. The note says the story is in review and its PRs now wait to be merged; it does
not say who merges them. No note goes for a review held on an open parent, for an epic's review, for
a story the swarm merges itself with `merge = agent`, or when the conductor ran the review itself.
With no conductor running, none is written. Its herdr calls stop after `SWARM_NOTE_HERDR_WAIT`
seconds, as a merge note's do. A herdr that cannot list its agents, or gives a list that does not
parse, or a note that fails, is a warning and never fails the review.

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
runs in the folder the session was in, so write `cd <dir> || exit 1 &&`. A `cd` in the condition of
a `while`, `until` or `if` is not read as one: it passes, and the commands after it are checked
where the call runs. It refuses a `git checkout`
that would overwrite uncommitted changes: unstaged ones, and staged ones too when it checks out from
a commit (`git checkout HEAD -- f`). Back the file up with `cp` and restore from the copy instead.
In a swarm project's main checkout (the git top level that holds `.claude/swarm/config`, not a
linked worktree), it refuses a `git reset --hard`, `git restore` or `git clean` that would drop work
there, and names the files. `reset --hard` is refused when a tracked file has a staged or unstaged
change, or when an untracked or ignored file is in the way of a file in the commit it resets to: at
the same path with other content, where that commit has a folder, or inside a folder where it has a
file. Any other untracked file passes, since `reset --hard` keeps it. `restore` is refused when it would
overwrite a change: an unstaged one, and a staged one too with `--staged --worktree` (`-SW`). With
`--source`, an untracked or ignored file in the way of a file it writes counts too, as for
`reset --hard`.
`restore --staged` alone changes only the index, so it passes. `clean` is refused when its own dry
run, with your flags, lists a file, so under `-x` or `-X` an ignored file in `.swarm/` counts.
`git clean -n` passes. Commit the changes in a board PR, or back the files up with `cp`. A clean
main checkout and any worktree pass.
swarm.sh starts every Claude agent with `SWARM_AGENT` set to its name. In an agent's session the hook
also refuses `git checkout`, `switch`, `restore`, `reset --hard`, `stash` and `clean` in the
project's main checkout, whether the command runs there from the session's folder, after a `cd`, or
through `git -C`. `git stash list`, `git stash show` and `git clean -n` change nothing, so they pass.
It also refuses an agent's `pkill`, `killall`, `kill $(pgrep ...)` or `kill $(pidof ...)`, and a
`kill` of PID `0` or a negative PID (`kill -9 -1` signals every process you own): any of them can kill
another session's process. `kill $!` and `kill <pid>` pass. It refuses an agent's `gh pr checks --watch` and
any `while` or `until` loop around `gh pr checks` (a `while read` loop that checks each PR once
passes), and names `swarm.sh wait-pr`, which stops on a red
check, a conflict or a deadline. A single `gh pr checks` passes.
Your own session has no `SWARM_AGENT`, so only the `cd`, `git checkout` and main checkout rules
apply to it. These
rules fail open: an error in them never refuses a call, even one whose command also says merge, and
a command that says `git` or `cd` but not merge passes when the check cannot run at all.

Every builder, review agent and conductor brief lists the forms the guard passes:
`cd <dir> || exit 1 && <command>`, a merge run alone in its call (the brief gives its own merge
command, or none under `merge = human`, so the rule names none), and the brief's own waits. A
builder's is `swarm.sh wait-pr --head`. A review agent's are
`swarm.sh wait --stall` and `swarm.sh wait-pr`, with `--head` after the builder pushes. A
conductor's are its own `swarm.sh watch --epic <epic>` (or `--backlog`) and `swarm.sh wait`, since
it never waits on CI. Text that mentions a merge goes through the Write tool, or into a `gh pr`
command as a quoted heredoc (`--body "$(cat <<'EOF' ... EOF)"`). A `gh api` call that carries it is
refused. The brief also shows a delete that auto mode ran for a builder with no permission prompt:
`rm -rf` on a scratch path spelled out in full. A path built from variables, `rm -rf "$SP/$m"`,
stopped a builder on a prompt. `tests/guard_forms_test.sh` feeds each of those Bash forms to the
guard.

An agent's guards come from the flags it starts with: `--disallowedTools` (no `gh pr merge`, and for
the fallback reviewer no file tools, commit or push) and `--settings`, which sets `SWARM_AGENT`.
When herdr restarts, it reopens each agent's pane and resumes the session. On its own it would run
`claude --resume <id>` with none of those flags, in the pane's whole environment. So as soon as herdr
has started a Claude agent, before its brief, swarm.sh gives herdr the command to resume it with
(`herdr pane report-agent --source swarm`, with the session id), so a pane whose brief is never
taken up has it too: `python3 -I <wrapper> claude --resume <id>` and
every flag the agent started with. The wrapper, and the command it starts with, are the session's
own, under `~/.claude/swarm-dev/resume/` (`$CLAUDE_CONFIG_DIR/swarm-dev/resume/` when that is set),
so the project's path is never in the command and a later agent of the same name never changes
them. The wrapper keeps only the allowlist the agent started with (§ Building, **The agents'
environment**) and its story's `env:` names, with the restored pane's own values, so no value is
written to disk or put on a command line. It is Python, not bash, so a `BASH_ENV` or an exported
shell function in that pane never runs. It also makes the session's own `ZDOTDIR` afresh, as the
first start makes the agent's, so nothing written there since runs in the restored agent's shells,
and restoring one session never touches another's. herdr refuses a resume command over 64 arguments or 8 KiB
(joined), or with an apostrophe or a control character in it, so swarm.sh checks those before a pane
opens and stops the start, saying which. It also stops on a herdr older than 0.9.2, which takes the
command and drops it. If herdr refuses the report itself, the agent has not had its brief yet, so
swarm.sh closes the pane and fails the start.

The plugin's hooks report an agent's state to herdr: working on each prompt and after each tool
runs (so an answered permission prompt no longer reads as blocked), idle when a turn stops or ends
on an API error, blocked on a permission prompt. Each report carries the resume command again. Only
the pane's own session reports, the one the command resumes. A `claude -p` that an agent runs from
Bash inherits the agent's variables, but its session is a different one, so it reports nothing and
never changes the command. The agent's own `/clear` moves the command to the new session; a nested
session's moves nothing. Each report has a
`--seq` of the time the event happened, taken before herdr is called, and herdr keeps the newest,
whatever order the calls arrive in. When you quit an agent's session yourself, the hooks hand the
pane back to herdr (`release-agent`). A session that ends because herdr restarts keeps its resume
command. Each hook calls herdr in the background, so a herdr that hangs never holds a prompt.

**Moving a running epic to a new version.** A running agent keeps the plugin version it started
on. After `swarm.sh update` (or `claude plugin update`) and a restart of your own session, run
`swarm.sh upgrade <epic>` to move that epic's agents (its conductor, builders and review agents) to
the installed version. `swarm.sh upgrade backlog` moves the backlog conductor and the stories with
no epic, and with no argument it moves every agent the project started. upgrade runs detached
until it is done: it starts itself again under `nohup`, in a process group of its own, and once
that worker holds the project's upgrade it prints the worker's pid and its log,
`.swarm/upgrade-<version>.log`, and returns, so closing the session that started it does not stop
it. A worker that stops first, as one that finds another upgrade running does, has its lines
printed and its exit code returned instead. `--foreground` runs it in your shell instead. One upgrade runs per
project. A second one, while the first runs, prints the running one's pid and log and starts
nothing. It exits 0 when the running one moves its agents too (the same epic, or every agent), and
1 when it does not: `<epic> was not moved; run it again once the running one ends`. A pid file
whose process is no longer a `swarm.sh upgrade` counts as none running. While it runs, `swarm.sh
status` names it, its epic, and that epic's agents not yet on the version it moves them to.
upgrade first checks the
conductor's `env:` names, as `conduct` does; if one is refused, it asks the conductor for nothing.
Otherwise the conductor writes a handover to `.swarm/handover-<epic>-<date>.md` (each open PR with
its review round, what its builder still owes, and findings it has not sent) and ends its turn. A
conductor already on the new version does this too whenever its builders will restart, so it never
acts on one mid-restart. An idle conductor is asked by prompt; a busy one gets a note in its inbox,
which it reads when its wait returns. upgrade works in rounds. Each round reads the agents again,
so one started meanwhile is moved too, and picks up a handover that came late: a conductor's
builders wait while its handover is not written or it is not idle, read again each round, since a
conductor whose turn ended can be woken by a background watch. A conductor that got the request in its
inbox and is idle with no handover is asked again by prompt, and one whose session is gone is named
at once. Each round restarts every builder that Claude Code reports idle, or whose turn stopped on an API
error, reading the session herdr has in the pane now (a `/clear` moves it), or the one `agents.tsv`
recorded when herdr lists none, as herdr 0.9.5 does; herdr's wait only wakes
it to check. Claude Code also reports `busy` for a session whose turn is over but whose background
shells (a `make test`, a `wait-pr`, a conductor's `watch`) still run, so a session reported busy is
read from its log too: when its last assistant entry has ended its turn, with no tool call waiting
for a result and no user entry after it (a prompt, a scheduled one included, or a tool result), it counts as idle and is restarted, its
background commands, subagents and monitors stopped (it is told to start them again). A subagent's own entries in the main log are not the session's turn. A turn still in progress, one
waiting on a tool call's result, one waiting on a prompt, and one whose log cannot be read stay
busy, are never interrupted and wait for a later round. A builder that goes busy between the round's
read and its restart is waited for one round (60 seconds) at most, then waits for the next, so a
round never stalls and the paused conductors' markers stay fresh.
upgrade skips closed agents. Before the first round acts on any agent, it reads Claude Code's list
of sessions once and uses it with the round's first read of herdr's list. An agent whose Claude
session is gone is skipped as closed. So is a Claude agent of the run whose pane a tab record in
`.swarm/state` names while herdr lists it in none of the project's panes (a pane closed by hand;
`swarm.sh` drops the record of a pane it closes). A session that goes later, up to the restart's own
idle check, is skipped the same way, a conductor's too once its handover is in. A conductor whose
session goes while upgrade waits for its handover is named as left, as below. A skipped agent is
never waited on, sent a key or restarted, and counts as neither moved nor left, so it does not fail
the run; its conductor hears it was skipped. All of them are named once, on one `skipped (closed):
<names>` line. When that first read of herdr's list fails, upgrade says the closed check did not
run; when Claude Code's list cannot be read, it says the check skipped no agent for a gone session.
Either way a session found gone later in the run is still skipped.
A builder also waits while its story's review agent (`review-<slug>`), which reviews its PR, is a
Claude agent on the old version that is not idle. The review agent is restarted once it is idle, as
any agent is. One left on the old version (its restart failed) still holds its builder while it is
busy. One still busy at the end of the wait is named as left, and so is its builder, with the reason
`its review agent review-<slug> stayed busy`; so is a builder its review agent held in the last
round, though that agent reads idle by the end. A codex review agent holds nothing, and neither does
a review agent skipped as closed.
A restart sends ctrl+c twice at once (Claude Code exits only on a second press right after the first) until
claude exits. It then starts claude again in the same pane: a fresh allowlisted environment whose
`PATH` starts at the new version's `bin/` (an older plugin root's is dropped), and `claude --resume
<session>` with the flags its claude ran with (`herdr pane process-info`). The session is the one
`herdr agent list` shows for the pane; when herdr lists the pane with none (herdr 0.9.5 lists none), it is the one
`agents.tsv` recorded, and the log says so. With neither, the agent is left on its old version and
its line names both sources. A list herdr cannot answer resumes nothing: the agent is left as it is. Once claude is back, upgrade gives herdr the resume command, as a first start does, so a herdr
restart keeps its guards. If process-info cannot be read, the agent is left as it is. A resumed session keeps its
context, so only the plugin root changes. Each restarted agent is told the new `swarm.sh` path,
since its brief names the old one, and that the restart stopped its background commands, subagents and monitors (a
`wait-pr`, a `codex-review`), to start again. The conductor goes last, told which builders were
restarted, which were left and which were skipped as closed: restarted and told to carry on, or, if it was already on the new
version or its restart failed before its claude exited, only told to carry on.
upgrade never touches a worktree, so uncommitted and unpushed work stays as it is. When it is done
it prints one line per agent: `<name>: <old> -> <new>`, `<name>: left on <old>: <why>`, or
`<name>: already on <new>` (with a reason, when a conductor already on it wrote no handover: it is
never left, and fails nothing), the `skipped (closed):` line when it skipped any, then `upgrade
done: <n> moved, <m> left (exit <code>)`, so a log
that ends without that line was cut off. Only an agent whose version changed counts as moved. The
run is logged as one event, the detached worker's, with its epic as the target. `swarm.sh version` in a pane confirms the version. If a restart
fails from the first ctrl+c on, upgrade leaves the pane open, and the agent's line names the
`claude --resume <session>` that brings it back and the folder to run it in. A conductor that
could not be told to carry on gets a line saying to tell it by hand. A TERM to the run (a HUP does
not reach it: the worker runs under `nohup`) names
each agent it had not moved as left (one cut off mid-restart with its `claude --resume` line), tells
each conductor it paused which of its builders were restarted and to carry on as before (one skipped
as closed is told nothing, and stays skipped), and ends
the log on `upgrade stopped: <n> moved, <m> left (exit 143)`. A KILL or a reboot
cannot, and leaves that conductor waiting for a prompt. An agent that leaves herdr's agent list
before it is moved is named as left, never forgotten; when it is a paused conductor, its builders no
longer wait on it. A session Claude Code reports as unknown (a bad read of its list) waits for the
next round, as a busy one does; a gone one is skipped as closed. A run that never reads herdr's list exits
1 and says no agent was moved. upgrade stops when every agent is moved or left,
or after `SWARM_UPGRADE_WAIT_MS` (2 hours, for the whole run). An agent still busy then is left on
its old version. A conductor with no handover by then, or still busy after writing one, is told to
carry on as before: by prompt once it is idle (upgrade waits up to `SWARM_UPGRADE_GRACE_MS`, 5
minutes, more for that), else in its inbox. Its builders are left with it, named for the reason:
their conductor wrote no handover, or wrote one but stayed busy. upgrade exits 1 when any
agent is left; a later run skips the agents already on the new version.

**Merge one at a time, unless the base has a merge queue.** After each merge, merge the base branch into every other open wave branch before
trusting its CI; a branch that conflicts gets no CI at all, which looks like a hang. A merge queue
tests each PR on top of the ones ahead of it, so there every reviewed PR can be enqueued at once.

**Keep with the lead:** real-cloud runs, credentials, and anything that changes permissions.

**Clean up.** After each merge, `swarm.sh reconcile` closes the story's builder and review agent if they are open and
removes its worktree and `story/<slug>`, here and on origin (§ Merging). By hand,
`swarm.sh close <slug>` closes a story's pane (its tab, when it was the last pane there) and keeps
its open PR, branch and worktree, putting a `ready` story in review with that PR (`kept:`). `--drop`
clears them on a `ready` story, one in review, or a held child (`blocked` with `held_by:`) whose PR
is open (§ Model and effort); on any other story it prints `not dropped:`.
`swarm.sh close conduct-<epic>` closes the epic's tabs. herdr closes a tab without asking, so close
first checks each tab's panes. It keeps a tab that holds an agent that is working or waiting, or
whose story has an open PR, and it keeps one when it cannot read an agent's state or gh cannot list
its PRs. It also keeps the tab that holds the pane the command runs in, unless that pane is the one
being closed, so a step-up or reconcile run from an idle review agent's pane leaves that pane open.
It prints each of those agents as `kept`, and still closes the conductor's own pane.
`swarm.sh close <name> [cause] [--drop] --all` closes the kept tabs as well.
close takes the full recorded name. It closes only what `.swarm/state` records under exactly the
name you give it: its pane, its tabs, and for a conductor the tabs of its epic, which its brief or
its full name gives. herdr and `swarm.sh` print agent names cut at 32 characters, so two long names
can look the same. A cut stands for a full name only when it is the one name the project's records
hold under it, counting the pane names in `.swarm/state`, the briefs in `.swarm/briefs` and the
stories together. When two names share the cut, it stands for neither: a conductor closed by such a
cut closes no epic's tabs, and close says so. An old brief whose name
shares a live slug's first 32 characters keeps that cut ambiguous while it stays, and close errs
that way on purpose: the pane is kept, or the close refused. A conductor named by its cut closes
the epic of the one name under the cut when that name is `conduct-<epic>` with a brief and no
story has it. With no name under the cut it closes the tabs of the cut minus `conduct-`, as it did
before, and the backlog conductor's cut is the backlog's. A tab close keeps an agent that herdr
lists under a cut, printing that its story could not be found, unless the one name under that cut
is a story's.
herdr's agent list stands in for a missing pane line only for a name shorter than 32 characters,
which herdr holds exactly: a longer name's cut may be an agent's with no record of its own. When
`.swarm/state` records nothing under a longer name and herdr lists a live agent under its first 32
characters, that agent may be another's. close then closes, counts, clears and keeps nothing, and
fails: close by the full recorded name, or close that pane by hand if it is the one you meant. With
nothing recorded and nothing live under the cut, there is nothing to close by mistake, so the close
goes on with no pane, as it does for a pane closed by hand.

## Releases

No story PR bumps `.claude-plugin/plugin.json`. Once main has changes since the last
release, `swarm.sh next` prints `release`: the project has `.claude-plugin/plugin.json`, the tag
`v<version>` for its version is on `origin/<base>`, and a commit since that tag changes a file
outside the board (for a board at the project root, outside its `stories/`, `epics/`, `hld/`,
`Board.base` and `.obsidian/`). It reads local refs only, since reconcile has just pulled. The lead opens a PR
from `release/v<new>` that bumps only that file, to the version `next` named (the stage's v<S>, or the patch it named). Only
when `next` printed a bare `release` does it bump to the next minor version (a patch when every
change since the tag is a fix). It lists the PRs merged since the tag. Before it cuts that branch, the lead lands a docs PR that covers
every behaviour change since the tag, and the release PR names it. When nothing since the tag
changes what a user runs, sees or has to do, a `Docs: none — <why>` line in the release PR body
stands in for the docs PR. For swarm-dev's own repo, the release PR body also lists the behaviour
changes every project gets on upgrade and names the infrafactory build they were tried on, or says
none. With `merge = agent` the
lead merges it with `swarm.sh merge --release` and checks that the tag and the GitHub release
exist. With `merge = human` it waits on your merge.

Epics can name the release they belong to with `stage: v<x.y.z>`. Once a release is due, `next`
reads the stages: the epics on the board, whatever their status, the copies `origin/<base>` has of
epics an edit in your checkout deleted or changed before it reached the base (a release ships the
base), and the epic files deleted on `origin/<base>` since the tag. The next stage S is the lowest one above the tag. When no epic of S
is left on the board, the step is `release v<S>`, and its why names the stage. While one is still
there, the release is held. `next` then prints `release-held: v<S>, open epics: <slugs>, patches
only` after its step's lines, and `status` and `dash` show the same line. A patch can still go out
while S is held. When no story of a staged epic has merged since the tag, and the next patch of the
tag's line is below S, the step is `release v<x.y.z+1> (patch)`. What merged under an unstaged
epic, or under no epic, goes out in that patch: nothing checks that it is a fix. A merged story is
one whose file was deleted since the tag (a story's PR deletes its file), or one the board keeps at
`status: done` that was not done at the tag. Otherwise there is no release step, and `next` goes on
to the steps after it. An epic on the board whose `stage:` is not
`v<x.y.z>` holds the release too, and the line names it. `merge --release` does not read the hold, so the lead cuts a
release only when `next` prints it. A board where no epic has `stage:`
releases as before, with a plain `release`. So does a board outside the project's repo, since git
can't list its deleted epics.

Staged draft epics wait for the stage before theirs. Take T, the lowest stage among them, and P, the
minor before it (v0.30.0 gives v0.29.0). Once the newest `v<x.y.z>` tag on `origin/<base>` is at or
above `v<P>` (local refs, as for `release`), `next` prints `stage v<T>`, with the why `set <slugs> active (board PR under the
epics grant)`. It comes after a ready one-off story and before a built epic's `conduct` and an active epic's `plan-epic`. While
a conductor works, `next` prints its `wait` instead. The lead opens a
board PR named `stage-v<T>` with the dots as dashes, which sets those epics `active` and changes
nothing else. It lands it with `swarm.sh merge --board` when `merge = agent` or the HLD grants
`merge`. Otherwise you merge it: the `epics` grant covers setting the epics active, not the merge.
While that PR's worktree (`<repo>-wt/_board-stage-v<x-y-z>`) exists, `next` goes on to the steps
after `stage`, and the gate, `status` and `dash` list `stage PR awaiting merge: v<T>`, whether its
epics are still drafts or the merge has made them active. The lead removes the worktree with
`swarm.sh board-pr done stage-v<x-y-z>` once the PR has merged or closed. Under `merge = agent` or a
`merge` grant, the lead waits for an open stage PR's checks from that row and lands it once they are
green. Under `merge = human` with no `merge` grant, you say not yet by leaving the PR unmerged:
`next` names no new stage PR while it is open. Closing it unmerged is not a no: the lead removes its
worktree, `next` names the stage again and a new PR opens. To take an epic out of its stage, drop
its `stage:` or `hld:`; it is then a plain draft, agreed through `/epic`. `hooks/lead-stop.sh` does not
know the `stage` step, so it allows the lead's stop on it, as on any step it does not list.

Once a release merges, `merge --release` reads its merge commit's first parent through gh, for 30
seconds at most. If that is not the base the release check last read, a PR landed between that read
and the merge, and the release shipped commits no check read. merge then prints `warning: <merge
commit>'s first parent is <sha>, not <sha>, the base the release check read, so it ships <commits>
unchecked` and logs it as a `merge` line in `.swarm/events.tsv`, whatever the repo and whatever CI
on the base says. When gh can't read the parent, it warns the same way.

When the release is swarm-dev's own (its repo is the GitHub repo named by `repository` in the
plugin's `plugin.json`; otherwise merge prints a line saying it skipped this step), `merge
--release` also updates the plugin and moves the agents onto it, once CI on the base is green. After
that warning it updates nothing, and prints `refused: the release ships commits no release check
read, so the plugin was not updated`, followed by what to run once they are checked. Otherwise it
waits up to 10 minutes (`SWARM_RELEASE_WAIT`) for the tag `v<new>` on the merge commit, or on a
later commit of the base, and a published GitHub release. Then it runs `claude plugin marketplace
update swarm-dev` and `claude plugin update swarm-dev@swarm-dev`, 5 minutes at most each. Once the
new version's `swarm.sh` is in the plugin cache, it runs that version's `swarm.sh upgrade`
(detached) in every swarm project where herdr runs an agent, and prints each upgrade's log path;
each one gets 2 minutes to start its worker. The old version's `bin/` is taken off that upgrade's
PATH, so each agent it restarts finds the new `swarm.sh`. An agent's project is the `SWARM_PROJECT`
its restore wrapper sets, so a builder of an external board counts; with no wrapper, it is the
project its folder is in, and with no agent in herdr's list, or a list it can't read, this project,
with a warning saying why. Last, it asks you to restart the lead session (`/exit`, then `claude
--continue`) in this project and in every project it found. The update is global, Claude Code loads
a plugin's hooks only at startup, and until a lead restarts, the `swarm.sh` on its PATH is the old
one. When CI on the base is not green, the release can't be confirmed or the update fails, it prints
a warning naming the new version's `swarm.sh upgrade` to run once the plugin is updated, and
upgrades nothing. An upgrade that fails, takes too long to start, or finds another upgrade already
running in its project and starts nothing gets the same kind of warning, and merge moves on to the
next project. The release still counts as done, and neither these warnings nor the refusal above
changes merge's exit code.

## Commands

| Command | What it does |
|---|---|
| `swarm.sh init` | Set a project up, from its git root: the board templates (a file that exists is left, except a `Board.base` that is a past template nobody edited, which it replaces with the current one and says `updated`, or stops when it cannot write the replacement; an edited one is left, with the `diff` command that compares it with the current template), `.claude/swarm/` with a commented `commit_trailers` line, the `.gitignore` lines, a `ci.yml` that runs `make check` on each PR and on pushes to origin's default branch, and fails when make has no `check` target, with a gate (`.github/swarm-board-only.sh`) that skips a PR or push changing only the board's own files (with workflows already there, it writes the gate and prints the step to add; a board outside the repo gets no gate; when origin's default branch can't be found, no CI), and a pre-commit hook that runs `make check` except on a commit that changes only the board's own files (when a hook exists or `core.hooksPath` is set, it writes none and prints the lines to add before any `exec`, or, for a global `core.hooksPath`, says to add them nowhere there). It ends by listing the files it wrote that git does not track yet, to commit. When no `permissions.allow` rule in Claude Code's settings lets `swarm.sh merge` run, it then prints your step to add `Bash(swarm.sh merge *)`. Until auto mode has learned your environment, it prints your step to run `/auto-mode-setup`, then `swarm.sh init --auto-mode-done`, which only records that you did, in `.swarm/auto-mode-done`, and writes nothing outside `.swarm/` (§ Merging, init's Claude Code checks). A second run changes nothing. |
| `swarm.sh upgrade [<epic>\|backlog] [--foreground]` | After a plugin update, move a running epic's (or the backlog's) agents to the new version: its conductor writes a handover, then each agent, once idle, restarts in its pane with `--resume`, keeping its context. It runs detached, in rounds, until every agent is moved or 2 hours pass, logging to `.swarm/upgrade-<version>.log`; one runs per project. It prints each one's old and new version and never touches a worktree. |
| `swarm.sh wait-pr [--timeout <seconds>] --head <sha> <PR URL>` | Wait for the checks on a PR's head and print the head SHA and each check. It exits 0 when all are green and 1 on red. Right after a push, GitHub can still report the old head. With `--head <sha>` (a full SHA or a prefix of 7 or more), wait-pr reads the PR again each poll until its head starts with `<sha>`, printing `pending: head <old>, not <sha>`, and reads no checks before then. If the head is still another one 5 minutes after the first read that found it (`SWARM_WAIT_PR_GRACE`), it exits 2, naming both. Without `--head` it waits on whatever head GitHub reports at its first read, so a wait started right after a push can end green on the old head before the new one has run a check. An agent that waits right after its own push passes `--head`. Green also needs a `pull_request` run of each workflow that a pull request into the base runs with the PR's files (its `branches` and `paths` filters). It reads the workflows once per wait, on its first read: at the PR's merge commit (`refs/pull/<n>/merge`), which is what GitHub runs them from, or at the head when that merge commit is missing or does not include the head yet. GitHub rebuilds the merge commit when the base moves, so a base commit pushed after the head that adds a `pull_request` workflow, or widens one's `branches` or `paths`, makes wait-pr wait on a workflow that never ran on this head. It then exits 2 after the grace, on every run, until you merge the base in and push. A workflow Actions has disabled is not waited on, and neither is one whose `types` leave out `opened` or `synchronize`. An expected workflow that has not started counts as pending, as `<path> (no run on <sha>)`, and so does one whose newest run has not finished, even when every check already there is green. If that newest run finished as anything but success, skipped or neutral, the head is red. A `push` run of the same workflow does not count. A workflow whose triggers it cannot read is not waited on, and a line of its own names it: `not waited on: <path> (triggers not read: <why>)`. It exits 2 when gh fails (a dropped connection, timeout or rate limit is retried first, up to 3 times in a row), at once when the PR conflicts with its base (`conflicts with <base>: merge origin/<base> in, then push`; GitHub's `UNKNOWN` on an open PR, still computing, is read again each poll, with the checks read beside it), when no check run appears within 5 minutes of the first read that found none (`SWARM_WAIT_PR_GRACE`) or an expected workflow still has no run by then (naming it), and when it is still waiting after `--timeout` seconds (30 minutes by default, `SWARM_MERGE_CI_SECONDS`), naming it; a read that hangs ends there too. Exit 1 always means a red check: any other failure, a bad config line included, exits 2. The first rate limit that comes while the budget it came from (GraphQL's for a `GraphQL:` error, else REST's) is spent is not retried that way: wait-pr prints `rate limited: GitHub's API budget resets at <time>; waiting until then`, waits until that time, moves its deadline back by the same amount, and starts its count of retries over. With `--timeout`, a reset past that deadline ends the wait at once, naming the reset time. A rate limit while the budget is not spent is GitHub's secondary, per-minute limit, sometimes in the same words. It is retried after the retry pause plus up to half again, so waits started together spread out, and the budget is not read again once the one reset wait is spent or the error says `secondary rate limit`. The no-check grace moves with the reset wait. It polls every 20 seconds (`SWARM_MERGE_POLL`), so run it in the background. From the story's review pane (`review-<slug>`'s, by the record `merge` and `tell` go by) with `escalate_ladder` set, a red head also counts toward the ladder's ci-red trigger, and the build's second red head steps it up, printing `stepped up: <slug>` ([§ The escalation ladder](reference-models.md#the-escalation-ladder)). |
| `swarm.sh review <slug> [--head <sha>] <PR URL>...` | Put a story or epic whose PRs are green and reviewed in review, with its PRs on its `prs:` line; a story whose `depends_on` parents are still open is held instead. With `--head`, it refuses, changing nothing, while the item has a PR it does not name: one on its `prs:` line or, for a story, one open from its branch `story/<slug>` (one review agent passes one PR). It then reads each PR's head (each gh read 60 seconds at most) and refuses unless every head is still `<sha>`, the head the review passed. A moved head needs a review of its own: the refusal names `swarm.sh review-agent --next <slug> <PR URL>` for a round that sent the builder findings, and a new `swarm.sh review-agent <slug> <PR URL>` after a pass. A read that fails says to run it again. A review that succeeds is logged in events.tsv as `review <slug> ok (<PR URLs>)`, with or without `--head`. With `--head`, when round N sent the builder findings and the head is still the one that round started on (not one a wording recheck passed), a `decline-only <slug> ok (round N)` line goes just before it: the builder declined every finding and pushed nothing. A `--head` review that succeeds also writes `review-finished <slug> ok` just before its own line. Each line carries `round=` and `verdict=` (`pass`, `decline-only`, or `held` on a refusal `held:`), as [§ Logs and outcomes](reference-logs.md#logs-and-outcomes) says. |
| `swarm.sh merge <PR URL>` | Merge a green PR whose story is in review, pinned to the head that passed, then wait for CI on the base branch and take the story off the board. With `merge = human` the lead runs it only for a PR whose agreed HLD grants `merge`, and you merge the rest. `swarm.sh merge --release <PR URL>` merges the lead's version-bump PR, which changes only `.claude-plugin/plugin.json`, and refuses it while the code changed since the last tag and the docs did not, unless its body has a `Docs: none — <reason>` line. With `merge = human` it merges only when at least one story merged since the last tag and every one of them is under an agreed HLD that grants `release`. It refuses a story PR, or a board PR under `--board`, that sets an epic `active` with no ticket (the epic guard, [§ Merging](reference-merging.md#merging)) or before the base allows its stage ([§ Writing an epic](reference-planning.md#writing-an-epic)). Where the base has a merge queue, `merge` enqueues the PR. Where it has none and the base gained code since the head's CI ran, `merge` has GitHub merge the base in, waits for the new head's CI and merges that head ([§ Merging](reference-merging.md#merging)). If CI on the base goes red on a commit it merged, it writes a `fix-main` story ([§ Merging](reference-merging.md#merging)). Under either merge mode it holds a story or `--board` PR whose own merge of the base dropped a line of the base, or whose merges it cannot check, and refuses one whose head moved on GitHub for a new review ([§ Merging](reference-merging.md#merging), Held for dropped base lines). |
| `swarm.sh dropped-lines <owner/repo> <n> <head> <base>` | Print the lines of `<base>` that PR `<n>`'s own merge commits dropped. It changes nothing and logs nothing. It works in the clone of `<owner/repo>` (the project, or `<repos_dir>/<name>`), whose origin must be that repo. It checks that gh lists `<head>` among the PR's commits, fetches `refs/pull/<n>/head` and `<base>` into refs of its own, and checks that the fetched commit is `<head>`. Then it scans each merge on `<head>`'s first-parent chain since the fetched `<base>`, with `git show --remerge-diff`, for a line the base side had that the merge dropped and the PR's own commits had not removed. It skips only the merges that `swarm.sh merge` recorded as `base-merged` in events.tsv: GitHub's own merges of the base, which it checked bring nothing else. Any other merge is scanned, a GitHub web-editor merge included. Each dropped line prints as `<sha7> <file>: <text>`. It exits 0 when nothing was dropped, 1 when it printed a line, and 2 when it cannot check: bad arguments, another origin, a head that moved or a stale fetch (naming both SHAs), git below 2.36, or a merge it cannot scan (an octopus, or one with neither parent on the base). |

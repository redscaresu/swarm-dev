# Reference: Logs and outcomes

Part of [the reference](reference.md), which lists every section and the file that holds it.

## Logs and outcomes

**The audit log.** Every `swarm.sh` command appends one line to `.swarm/events.tsv`: the time,
the command, its target, the herdr pane that ran it, and how it ended: `ok`, `interrupted`, the first
line of the error that stopped it, or `failed (exit N)` when the error came from a nested step, whose
message a caller may have handled (it still reaches the terminal). Only the read-only commands are
exempt (`READ_ONLY_COMMANDS` in `bin/swarm.sh`: `dash`, `status`, `next`, `config`, `policy`, `grants`,
`cost`, `outcomes`, `flow`, `dataset`, `review-yield`, `features`, `lessons`, `findings`, `dropped-lines`, `where`, the `wait`, `wait-pr` and `watch` that conductors and the lead run all the time, `base`, and
`tidy` without `--yes`), so a new command is logged until someone names it read-only. The
exception is `wait`, which logs each nudge it sends as `nudge <agent>` and each API-error resume as
`resume <agent>`, and `wait --lead`, which logs each Enter it sends an unsent brief as `resend <agent>`.
The stall rule skips those lines, because none is a sign of life. `status`, `next` and `dash` log
their run times to a file of their own (the run-times log, below). Something that went wrong is an `incident` line,
its outcome `<kind>: <detail>`, which `flow`'s `incidents` section counts. `wait` writes two kinds:
`wait-timeout` when its wait runs out (not when herdr's wait fails sooner, not for a
`wait --until-report` hour that it waits again, and not while the agent is still working: its
session `busy`, or, for an agent herdr answers for, herdr's `working`), and `login` when it returns `auth`, once per
expired login: a second wait adds none, and a `tell` (the resume after the `/login`) starts a new
one. `tell` writes `stale-blocked` when herdr refused a tell as blocked though the agent's pane read clear,
so `tell` reported the agent idle to herdr. A `close` that ends a build with no open or merged PR on `story/<slug>` writes `idle-no-pr`,
unless its cause is `stalled`, `paused`, `cleared-on-error` or `impossible`; the waits on that builder write
none, so one stuck builder is one incident. `wait --stall` writes `sign-blocked` when a builder it would otherwise call
stalled, with no sign of life for under 3 times `stall_minutes`, cannot sign its uncommitted work, and `sign-clear` when that builder can sign again, each once per change of state
([§ Building](reference-building.md#building)). Neither ends a login episode. `swarm.sh intervene <kind> <cause> "<one line>"` writes one with
target `-` and the outcome `<kind>: <line>`, for each time a person had to step in: `lead-hand`
when the lead did by hand what a command should have, `user-caught` when the user found a problem
first. The cause says why they stepped in. It is one of `INTERVENE_CAUSES` in `bin/swarm.sh` and goes
in the field `cause=<cause>`. Any other kind or cause, an empty line, or an events.tsv it cannot write
fails and writes nothing, and an unknown cause's error lists the causes. The old form,
`swarm.sh intervene <kind> "<one line>"`, still writes the line with `cause=none` and prints the causes
as a warning.
A `reap` line records something swarm-dev killed for running too long. Its target is what was
killed and its outcome says why. `codex-review` writes one when `codex_minutes` runs out, with target `codex-<story>` (`codex-<base>`
with no `SWARM_STORY`) and the outcome `timed out after <N> min`. `make test` writes one when a test file runs past
`TEST_FILE_TIMEOUT`, with the file as target and the outcome `TIMEOUT after <n>s`, to the events.tsv beside the run's `test-runs.tsv`;
a nested run, whose runs log is set empty, writes none. A command that finishes in time writes no `reap` line. Only those two write it. A fallback reviewer, or its agent when it writes no findings in time, is killed with no `reap` line, so the count is not every kill. When `status` or `wait` reads an agent's pane, herdr
says its turn ended (idle or done), and the turn ended on an `API Error:` line or on the tool result
Claude Code gives for a denial (`Error: Permission for this action was denied by the Claude Code auto
mode classifier.`), it writes `api-error` or `auto-denied` with that line, once per stop. An `API
Error:` line counts only after `⏺` or `●` at the margin, where Claude Code prints its own. An agent's
own indented text does not count, and neither does a tool's output (`⎿`) that prints `API Error:` or
quotes the denial. `next` and `tell`
only read. `status` and `wait` keep `.swarm/panes/<agent>`: the pane's checksum, when they last saw it
change (which `dash` shows), and which stop was logged last. Stops are told apart by the lines from
the last prompt above the stop down to it, or by the stop's line alone once that prompt has scrolled
out of the window.
The record drops it when a read of the pane shows no stop. Reading the same stopped pane again, after
it scrolls or after a resume it has not shown yet, adds nothing. A stop after a new prompt is a new
one, even when the resume and the second error both come between two reads. A retired agent's record moves to its new name, and a new
agent of the name starts with none. The stall rule skips incident lines as it skips nudges and resumes. A `tell` is logged as `tell:<kind>` with the slug as
its target, or as plain `tell` when the kind is missing or wrong. One that reached the builder counts as a swarm action on the story. The stall rule
skips `tell:nudge`, since it is a nudge too, and any tell that ended other than `ok`, since it never
reached the builder. It also skips `tell:note`: a note the lead leaves a conductor says nothing about
whether the conductor is working. A `close` with a cause is logged the same way, as `close:<cause>`, and one with
no cause as plain `close`. A close with an unknown cause is refused and logged as plain `close`,
and the word that was given never reaches the log. `reconcile` and `unblock` write a line
per item they move. `merge` writes all its own lines, under the story's or epic's slug (the PR URL
with `--board`, or before it knows the item): a refusal is one `merge` line saying why, and nothing
else (a hold for the user, `held: ...`, ends in a `hold=` field: `hold=protected` for a protected path,
`hold=money` for a `costs:` line, and `hold=dropped-lines` when the PR's own merges of the base dropped
base lines or could not be checked for them; no other refusal has a field); each merge of the base into the PR's branch is one `merge base-merged <new head> from <old head>` line, before the `merge ok` or the refusal that follows it, or `merge merged elsewhere` when the PR merged during the wait, by another `swarm.sh merge` or by hand (§ Merging); a PR that `gh pr merge` ran on but that never reads as merged is one `merge unconfirmed
(<state>)` line; otherwise `merge ok`, then `main-ci` with `ok`, `red <checks>`, `timeout (<what it waited on>)`
or `error <why>` (a red one followed by `main-red`, target the merge commit, outcome its repo, base and checks;
an ok one that clears a red main of that repo and base by `main-green`, outcome its repo, base and
the red commit it clears, and a `fix-main` line,
outcome `retired: <why>`, for each unstarted fix-main story that retires), then reconcile's lines. Before an ok `main-ci` comes a `flake` line for each run whose rerun went green, outcome `<jobs> <run URL>: <FAIL lines>`, a record that no command reads yet. Through a merge queue (§ Merging) it is the same `merge ok`,
`main-ci` and reconcile lines, or a single line: `merge dequeued (<reason>): <checks>`, `merge closed while
queued`, `merge the head is <sha>, not <sha>, the head that was checked; ...`, `merge gh pr merge
--auto failed: <error>`, `merge could not read whether <base> has a merge queue: <error>`, or `merge
unconfirmed (<why>)` for a timeout (`timeout (<what it waited on>)`), an error, a PR never read as
queued, or a merge with no merge commit. A merge at a head other than the checked one is `merge
merged at head <sha>, not <sha>, ...` and then reconcile's lines. A `story` that starts an `escalate` build, and the `close` that hands its story to
the lead, each write one more line of their own (§ Model and effort). The plugin's merge guard
(§ Merging) writes an `incident` line, target `-` and outcome `merge-blocked: <form>` or `guard-blocked: <form>`, for each call it blocks.
`reconcile` writes one, target `-` and outcome `pull-failed: <files>`, when changed tracked files stop
its pull (§ Merging), once while the same stop lasts, and one with outcome
`key-dropped: <file> <key>: <yours> -> <theirs>` for each uncommitted `status` or `prs` its pull replaced. The log is local to the machine and append-only,
holds names and paths but never a brief's or a message's contents, and a write that fails never
fails the command. The outcome field is the one place free text gets in: the reason given to a
`reset` or `drop`, the answer given to `dialog`, the PR URLs a `review` names (`ok (<PR URLs>)`),
and the first line of a failed command's error.

The outcome field can end in a tail of `key=value` fields, for example
`ok (round 2) ~~ round=2 verdict=pass`. The separator is ` ~~ ` (a space, two tildes, a space),
`EVENT_SEP` in `bin/lib/agents.sh`. `append_event` writes the tail only for a caller that passes
fields; `merge` passes `hold=` on its held lines, and `intervene` `cause=` on its incident lines. It first takes every separator out of the outcome text: each
one becomes a space. It also drops a trailing ` ~~`, which the tail's separator would complete, and
then any trailing spaces. That way the first separator in the field is always where the tail starts,
and an outcome that ends in one is written without it. Fields are separated by spaces. A key is
lowercase letters and `_`. A value is not empty and holds no whitespace.
A pair that breaks these rules is left out, with a warning on stderr, and the line is still written
with the valid pairs. Readers strip the tail with `outcome(row)` in `bin/lib/events_outcome.py`
(`fields(row)` there returns the fields as a dict) or with the awk function `outcome(s)` in
`EVENT_OUTCOME_AWK`. Rows written before the tail existed have none, and both return their outcome
unchanged.

**The run-times log.** Each `status`, `next` and `dash` run appends one row to
`.swarm/run-times.tsv`: when it started (UTC), the command, the seconds it took (to the millisecond)
and the 1-minute load average at its start (`-` when `uptime` gives none). Nothing else writes
there: `_step`, which the lead's stop hook runs, and the polls of `wait --lead` read the board as
`next` does but log no row. A `dash --watch` logs its first frame only. A `swarm.sh` run under a
timed one (each project `dash --project` draws, the `status` that `dash --check` reads, a watch that
restarts itself on a new version) logs none, so a run is one row. A run that fails logs none, nor
does a watch whose first frame failed, a project with no `.swarm/` yet, or a `dash --project` run
outside any project. A clock or a write that fails never fails the command. `flow`'s `run_times` section reads it.

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
computes rework; `flow`'s `model_fit` and `reviewers` sections read this column. The next column,
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
retry, whose own wait is not counted. After it, `ready_wait_min`, also on a first build alone, is the
whole wait from that ready time to the build's start, with or without a conductor running. A story
with no ready signal before its build started (it was readied only after) waited 0. Otherwise it is
empty where `held_min` is for want of a ready time. A step-up rung keeps attempts at 1, so it carries
its own `held_min` and `ready_wait_min`, timed to its own start; `flow`'s `time_in_state` counts each
story once, by its earliest build. The last column, `green_to_review_min`, is the minutes from the
later of the PR's head going green and the PR opening to its next review round's start; § time_in_state below says how. A story the lead holds after an escalation (`kind: lead` with
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
agent has none to keep, and neither has an agent whose name runs past 32 characters: `agents.tsv` keeps
only the cut name, whose newest session may be another agent's that is still running. Nothing is redacted, because a list of what to scrub misses whatever it
doesn't list, so the copy holds whatever the session held. The copy is readable by its owner only,
and `.swarm/` is git-ignored: the archive stays on the machine, and is never committed or uploaded.
Flow's `cost` section and `outcomes` read a session's live log while it exists and this copy once
Claude Code has deleted it, matching the copy on its session id, so their tokens, cost and slugs
outlast the 30 days. The stall rule, the goal check and `dash` never read the copy: an archive is
no sign that an agent is alive.

## Flow and features

`swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>] [--no-cache]` prints the project's
numbers in sections, one per `bin/lib/flow_<name>.py` in name order, each under a `## <name>` line:
`ci_health`, `cost`, `epic_totals`, `features`, `gh_calls`, `holds`, `idle_slots`, `incidents`, `lead_queue`, `merge_ins`, `merges`, `model_fit`, `predictions`, `review_loops`, `reviewers`, `run_times`, `start_failures`, `test_runs`, `throughput` and `time_in_state`. Each section gets the window (`--since` and
`--until`, which must be real dates, and `--epic`), the log paths and the `outcomes` rows, and calls
`gh` itself if it needs to. A new section is a new file, so adding one changes neither `flow` nor
the others. `flow` writes nothing but its own gh calls' lines in `.swarm/gh-calls.tsv` and its cache (below), except that `merge_ins` may fetch a PR's head into its repo, and its `git merge-tree` writes the trees and blobs of each re-merge into the repo's object store. For one release, the old `cost`, `features` and `review-yield`
commands still run, and each prints which section now holds its numbers.

GitHub history that is finished never changes, so `flow` (and dash's ci refresh, which runs it)
reads it from `gh` once and keeps it in `.swarm/gh-cache/<owner>--<repo>/` (`bin/lib/gh_cache.py`),
one JSON file per record: a merged PR; a closed PR's commits and runs, once `gh` lists some runs and
none of them is still running; a completed run's jobs and earlier attempts; the `FAIL` and `TIMEOUT`
lines of a red attempt's log (never the whole log, and never an empty answer, which comes back while
GitHub is still archiving a log); a PR's `createdAt` and branch; the merged PRs `rework` searches,
for the last 120 days; and the repo's completed runs that the flaky tests read, for the last 90 days
(each kept for the window, if longer). An open PR and a run still in progress are read fresh every time. A closed PR that was not
merged can be reopened, so it is read again every time, and its commits and runs are read again
once its `updated_at` moves; records kept under an earlier `updated_at` are deleted then.

The two listings ask `gh` for the window while nothing is cached, then only for what is new, and the
window is served from the cache. Merged PRs are searched from a day before the newest cached one's
day, because GitHub's search can list a merge late. Runs are listed from three days before the
newest cached one's day, or from the oldest day with a run still running (a run queued for over a
day holds nothing), or from the window's start when that is later. A run listed again while a rerun
of it is running is dropped until the rerun ends. A rerun keeps its run's creation time, so a rerun
of a run created more than three days before the newest cached day is not seen. A runs listing
that GitHub cuts at 1000 (the newest) is listed again up to the oldest day it reached, until it is
whole; only a single day of more than 1000 runs is left out. What a cut listing leaves out (the
merged PRs before a cut list's oldest, or such a day of runs) is kept as the cache's hole, listed
again first on every run whose window reaches it, and every such run that finds it still cut says
so: a `flaky tests:` line, or `rework` unknown for the PRs merged before the cutoff. A file is written to a
temp file and renamed, so a parallel `flow` never reads half of one; one that cannot be read or
parsed is read from `gh` again and rewritten, and one that would not change is not written.
`--no-cache` reads nothing from the cache, `.swarm/outcomes-prs.tsv` included, and writes what `gh`
answers over it, so it also shows a rerun the cache missed. Setting `SWARM_GH_CACHE` empty turns the
cache off (the tests whose `gh` stub changes between runs do).

The `ci_health` section prints one TSV row, `prs heads ci_min_median red_runs_per_pr flakes`, over
the github.com PRs of the `outcomes` rows dated in the window (with `--epic`, that epic's); a PR
elsewhere, such as GitHub Enterprise, is left out. Each PR costs three or more `gh` calls, so without
`--since` the window is the 30 days up to `--until` (or today), and a line above the row says so. For each PR, `gh` gives its commits and its
branch's completed workflow runs, and a run counts when its head is one of those commits. `ci_min_median` is the median, over head SHAs, of the minutes from a head's first run
created to its last run updated. `red_runs_per_pr` is the red runs (a failure, a timeout or a run that could not
start; a cancelled or skipped run is not red) over the PRs. `flakes` counts each red run followed by a green one of the
same workflow and event on the same head, so a workflow red on push and green on pull_request is no
flake. `gh run list` shows only a rerun's last attempt, so the section reads each earlier attempt's
conclusion from `gh api`. A run whose times do not parse adds no minutes. It reads each PR over gh's REST API, whose hourly limit is separate from the GraphQL one a swarm's `gh pr` commands spend. A reset connection or a 5xx is tried three times, 1 and then 2 seconds apart. Any other error is not tried again, and after `API rate limit exceeded` the section makes no more `gh` calls. A PR that `gh` cannot read, or whose call takes over 10 seconds, is left out of the row. A line under the row says how many, and a `ci health: left out <PR>: <the gh call>: <gh's last line of error>` line names each one. The ci time table below does the same with `ci time:` lines.

After the ci time table, so its reads never starve that table, a `test_file flaky_runs last_seen example_run` table names the test files that
fail and then pass on the same commit, worst first. It lists the runs created in the window, one
`gh api` call over GitHub's UTC days, in the repos of the window's PRs (one `gh` could not read
too) and in the project's origin, so runs on main and on the lead's own PRs count too. With `--epic`, it reads only that epic's
PRs' runs. A flaky run is the one `flakes` counts: a red attempt that a green one on the same head,
workflow and event follows, in the same run or a later one. For each one, `gh run view --log-failed`
gives its red attempts' failed steps, and each of `scripts/test.sh`'s own lines for a failed file,
right after the log's `<job> <step> <timestamp>` prefix
(`FAIL tests/<file> <n>s`, `FAIL tests/<file>: its job ended without a result` or `TIMEOUT
tests/<file> after <n>s`) counts that file once for the run; a test's output that quotes, indents or diffs such a line
does not. `last_seen` is the day the file's latest flaky run was created,
and `example_run` links that run's attempt. It reuses the attempts the row already read, reads the
newest runs first, makes at most 100 `gh` invocations (not REST requests: the listing pages up to 10,
a log download takes several, and a 5xx is tried up to 3 times), and stops at `API rate limit
exceeded`, keeping what it read; a `flaky tests: stopped at` line names the repos it did not list
and how many runs it left. Lines starting `flaky tests:` also say when GitHub listed fewer runs than the window has (it
lists at most 1000), name each run or log `gh` could not read, count flaky runs whose logs have no
such line among those whose logs were read (`go test` or `pytest` output, say), and print `none in
the <n> runs read` (each run once) when every listing was read in full, nothing stopped, and
nothing was flaky.

The `cost` section shows where the tokens went: tokens and estimated cost per role for the agents
started in the window, with a `lead` row for your own sessions (by their first timestamp's local
day). With `--epic` it still counts every agent in the window, and says so.

Under `### per rung` it then prints one row for each step-up of the escalation ladder logged in the
window (an `escalate` line such as `ok (findings-3: opus -> fable)`). A row gives the trigger, the
two models, the tokens and estimated cost of the story's builder sessions on each rung (the
`agents.tsv` lines for its builder, summed by model; `-` for a rung with no session log), and how
the build ended. The ending comes from the story's `outcomes` rows, so a PR merged on GitHub or by
another run counts as `merged` with no `merge` line of this run. It is `lead` when the story was
held or escalated for the lead after the step-up and before its next build started (a `held`,
`escalated` or `close:impossible` line). It is `failed` when the story was built again or its last
rung closed with no PR open (as far as `gh` could tell), and `open` otherwise, including a story with no `outcomes` row yet. A
window with no step-up prints `none`. A second table then gives, for each rung, how many builds in the window reached it and their
share of all builds in the window. A build is a story's attempt, and a step-up's new rung is part of
the same attempt. With `--until`, neither table counts a session or rung that started after it.

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

The `merge_ins` section says why the PRs that `epic_totals` counts under `main_merged` merged their base
in: the PRs of the window's outcomes rows (or `--epic`'s), one row per PR, that merged with
`main_merges` above 0. With neither `--since` nor `--epic` it reads the 30 days up to `--until` (or
today), as each PR costs two `gh` calls, and a line says so. It reads each PR and its commits over gh's
REST API, with `ci_health`'s retries and its stop once the hourly limit is spent. A merge-in is a commit
whose headline merges the base in, the same rule `main_merges` counts by. `git merge-tree` re-merges the
commit's two parents in its story's repo (its `repo:`, or the project). When the commit is not there and
the repo's origin is the PR's repo, the section fetches the PR's `refs/pull/<n>/head` from origin once,
and a `merge ins: fetched` line says so. Every git call it makes runs as `dataset`'s fetch does: with no
prompt, ssh in batch mode, and a 60-second limit. A merge that conflicts is `conflict`. So is one git
merges clean but whose commit differs from that clean merge on a path the PR changes, a fix made by hand
before committing; a difference on other paths comes from another merge strategy (GitHub's "Update
branch", an older git) and counts as clean. A clean merge is `behind` when the base had commits the
branch lacked, and `neither` when it had none. `unread` counts a PR `gh` cannot read or whose answer
names no base branch, the merge-ins `main_merges` counted that `gh` does not list, a sha that is not 40
hex digits, a commit git cannot find, a merge-in whose `git log`, `merge-tree`, `diff` or `merge-base`
fails or runs out of time, and a "merge" with one parent (a squash or a rebase); a `merge ins: left out
<PR>: <why>` line names each. It prints TSV `cause merge_ins prs`, a row per cause (a PR with merge-ins
of two causes counts in both), then `file conflicts`, the three files conflicts and hand fixes hit most
(control characters dropped from the names); or `none conflicted`, or `none read` when it read no
merge-in.

The `merges` section reads `events.tsv` alone. Its first table, `day finished`, gives the stories
finished per local day: a `finish` line with outcome `ok`, or a `reconcile` line whose outcome starts
`ok (finished`. Each slug counts once, on the day of its newest such line. dash's speedometer shows the
same count. After a blank line comes `day dropped_lines protected money unmarked`: the `merge` lines
whose outcome starts `held:`, per local day, counted by their `hold=` field (§ Logs and outcomes). A
held line with no field, written before `merge` passed one, counts under `unmarked`, as does one with a
kind the section does not know. So a 0 in the other three means none of that kind was held. A day with
no held line has no row. `--epic` does not narrow either table.

The `gh_calls` section shows how the swarm spends GitHub's two hourly budgets (5000 GraphQL points
and 5000 REST requests). swarm.sh puts `bin/gh-shim` first on its own PATH and on every agent's, a
restored agent's too. The lead's own gh calls outside swarm.sh, and a person's, do not go through it
and are not counted. The shim runs the real `gh` with the same arguments, stdin and exit code (an
INT ends it and exits 130, as an interrupted gh would), then appends a line to the project's
`.swarm/gh-calls.tsv`: the UTC time; the agent (its name, or `-` outside any agent); the via
(`swarm.sh <command>` when swarm.sh made the call, a builder's `swarm.sh wait-pr` among them, else
`-`; the outermost command's, so what a command runs through another swarm.sh, such as `dash
--check`'s status or `merge`'s wait, counts as the command that caused it, while an agent's own
swarm.sh starts afresh); the subcommand (`pr view`, `api graphql`, or `api <path>` with the query
and any host cut off and each path segment that holds a digit shown as `:id`, flags before either
word skipped); the budget (`graphql` for `api graphql`, `status`, `label list` and the `pr` (except
`pr diff`), `issue`, `repo` and `project` groups; `none` for a run that spends neither budget:
`config`, `alias`, `completion`, `browse`, `help`, `--version`, any `--help`, a bare `gh`, `auth
token`, `auth git-credential`, `auth setup-git`, `api rate_limit` and `search`, which has a limit of
its own; `rest` for everything else); `many` (`paginate` for `--paginate`, `watch` for `--watch` and
`run watch`, else `-`); and the exit code. It logs nothing past the subcommand and API path, so
never a token, body or header, and a log it cannot write never fails the call. The read-only
commands (`dash`, `wait-pr`, `watch` and the others) log their gh calls there too; it is the one
file they write under `.swarm`. A row counts gh runs, not API requests: a `many` run spends several
requests, and a GraphQL query costs a point or more, so the share is a floor. The section prints a
line saying so, and that role `-` is a call outside any agent and share `-` a `none` run; then TSV
`hour api role runs many share`: for each local hour in the window and budget, an `(all)` row, then
one row per role (the agent's `agents.tsv` role; an agent it does not name as itself; `-` outside
any agent), most runs first, with how many were `many` runs and the share of the 5000 (`<0.1%` below
that, and `-` for `none`). After a blank line it prints the same per subcommand, `via swarm.sh
<command>` added when swarm.sh ran it. With no log yet, or no lines in the window, it prints a line
that says which. The section reads the log from the end and stops two days before `--since`. The
shim keeps the log from growing without end: about one call in 1000 counts its lines, and past
50,000 keeps the newest 50,000. GitHub's hour starts at a budget's first call, not on the clock, so
one hour here can straddle two of GitHub's. `--epic` does not narrow it.
The `incidents` section prints TSV `day kind incidents`: the `incident` lines in events.tsv
(§ Logs and outcomes) counted per local day in the window and per kind, whatever the kind, one row
for each pair with any. An incident's target is an agent name, which can be cut short of its slug,
so `--epic` does not narrow it. After a blank line, TSV `epic kind stops` counts the `api-error`
and `auto-denied` lines per epic: a builder's or `review-<slug>`'s epic is its story's, a
`conduct-<epic>`'s its epic, as `outcomes` gives them, and `-` when none does. `--epic` keeps that
epic's rows. Three more parts follow, each after a blank line, over every epic. TSV `kind cause
incidents` counts the window's incidents per kind and `cause=` field, which `swarm.sh intervene`
writes; a line with no `cause=` counts under `-`. TSV `time agent bg test sign` lists each `stalled`
incident with its `bg=`, `test=` and `sign=` fields as written. A field the line does not have
was not measured and prints `-`, not 0. The last line is Goal 3's bar, `false stalls: <n>
(<a> stalled with an input at 1, <b> lead-hand or user-caught with cause=false-stall)`. `<a>` counts
the stalled incidents with any of the three at 1, and `<b>` the `lead-hand` and `user-caught` lines
with `cause=false-stall`. The bar is 0.

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

The `predictions` section scores the planner's `easy` labels and `estimate_lines` against what the
builds took. It reads `.swarm/dataset.jsonl`, which `swarm.sh dataset` writes, and counts the stories
merged in the window. With `--epic`, it counts only the stories whose text has that `epic:`. It prints TSV `planner_model stories easy_precision easy_recall estimated
est_err_median est_err_mean`, one row per planner model (`-` when `dataset` found none) and a last
`all` row:

- `easy_precision`, of the stories labelled `easy: true`, the share that `was_easy`;
- `easy_recall`, of the stories that `was_easy`, the share labelled `easy: true`;
- `estimated`, the stories with both an `estimate_lines` and a diff size;
- `est_err_median` and `est_err_mean`, the median and mean number of lines those stories' estimates were off by.

Both shares print as `hits/total percent`, or `-` with none to count. A story whose `easy` or
`was_easy` is unknown counts in neither. A window with no stories prints a line saying so in place of
the table. A last line counts the file's lines the section could not score: lines that are not JSON,
or that have no `inputs` and `results`. With no `.swarm/dataset.jsonl`, the section prints a line
saying to run `swarm.sh dataset`.

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

The `time_in_state` section prints TSV `epic prs hours largest_first ready_wait_median ready_wait_p90
green_to_review_median green_to_review_p90`, one row per epic and a last
`all` row. With `--epic` it prints that epic's row alone. The five phases are summed over the
`outcomes` rows dated in the window that have the phase columns (their PR merged). Each PR counts
once, by its build that started first, since a retried PR repeats its phases on every build, and is
in the window only when that build's date is. `held` is over the same PRs: the `held_min` of each of
their stories, once, from its earliest build. `hours` is all six together, and `largest_first` gives each as
`<state>:<hours>h/<share>%`, the largest first, where the share is of `hours`. So
`held:3h/64% review_wait:0.6h/12% fixing:0.4h/9% ci:0.2h/5% merge_wait:0.2h/5% building:0.2h/4%`
says the epic's stories spent most of their time waiting to start. The next two columns,
`ready_wait_median` and `ready_wait_p90`, are the median and 90th percentile (nearest rank) of
`ready_wait_min` in minutes, over the stories whose first build is dated in the window, merged or
not. They are empty when there is none, and an epic with only such builds still gets a row.
The last two, `green_to_review_median` and `green_to_review_p90`, are the median and 90th
percentile of `green_to_review_min` over the row's merged PRs, the ones the phases count, and empty
when none has one.

`green_to_review_min`, the last `outcomes` column, is the minutes from the later of a PR's head going
green and the PR opening to the first review round that started after that, before the PR closed.
A round starts at an events.tsv `review-agent` line for the slug, a review agent's start, whose
outcome is a bare `ok` (today the conductor starts an agent so for every round, and the agent waits
for green itself, so a start can come before the head is green), or at a `review-agent:next` line,
a round run in the same session, whose outcome is `ok (round <n>)`; only those lines carry the
round, though a `review-agent` line that did would count the same. A start before the head's green
is not after it and does not count, and a round before the PR opened is an earlier PR's of the
slug. The head went green at the end of its last check run, and
only when every run on it concluded `SUCCESS`, `NEUTRAL` or `SKIPPED`. gh gives the runs of the PR's
latest head alone, so an earlier head that failed counts for nothing and a later head counts from
its own green. A head pushed after the last round, as a base merge before the merge often is, has
no round after it, so the column is empty and `time_in_state`'s median and p90 leave that PR out. A
check rerun on the same head after a round started moves its green past that round, so the column
then runs to the next round, or is empty. A run that failed, is still going or has no conclusion
means no green. A commit status counts at the time it was set, and a green entry with no time at
all leaves the green unknown. A PR record cached before conclusions were read has none, so its
green is unknown, and so is every story that finished before this column existed, until
`flow --no-cache` reads their PRs from gh again and rewrites the cache. The column is empty with no
green, or no round after it.

The `idle_slots` section asks whether the swarm sat idle while work was ready. It prints TSV `epic
idle_min no_conductor_min most_ready`, one row per epic and a last `all` row, or the `--epic` row
alone. When no story (or none of that epic) waited in the window, the line `no story was ready in
the window` (or `no story of epic <slug> ...`) replaces a row of zeros; a story covered by its own
running build did not wait. `idle_min` is the minutes in the window when at least one of the epic's
stories was ready with no build while its conductor ran. A story goes ready at an `unblock`,
`reconcile ... ok (reopened)`, `reset` or `reset:held` event, or at a close that sent it back to
ready. That is any close except the first one after a `review` or `kept` event for the build, which
leaves the story in review (a later close, the drop, sends it back). Every wait counts: the first
runs from the first build's start less its `ready_wait_min` (or from a later event that readied the
story, such as a reset), and each later one from the story going ready again to its next build. A
story is not waiting while its own build runs. A story on the board now that `next` would build
(`status: ready` with `.swarm/board-state` laid over its file, a kind an agent builds, no epic or an
`active` one, and not held) with no build since it went ready waits until the end of the window. A
build since is one that ran past that time and started at it or later; a build the readying close
ended, however short, is not. For that wait, the board's last commit to its status line on the
default branch, dated by the merge, also readies it. A ready story that clashes with a running build
(their `touches` in the same repo, as the clash rule reads them, with the project's `repos_dir`,
unless one depends on the other) could not start, so those minutes are not idle. A build from before
`--since` still clashes: its story is read from the board or, once merged, from git. When a git call
fails, the section warns once on stderr, as what it reads is then left out. The same minutes with no
conductor of the epic running go under `no_conductor_min`. `most_ready` is the most of its stories
ready with no build at once, clashing or not. The `all` row counts a minute once however many epics
were idle in it, and it includes the stories with no epic, under the backlog conductor. Builds keep
`agents.tsv`'s order. Each runs from its start to its slug's next ok close or `reconcile ... ok
(finished...)` (reconcile closes a merged story's builder itself), else to its next build, else to
the end of the window. A build with no session log yet starts at 00:00 on its `agents.tsv` day, and
no earlier than the build before it ended. Such a build counts as built since its story went ready,
unless a close readied the story. A conductor runs as `held_min` reads it: from an ok `conduct`
event until the next one, a close of its agent or its report. A backlog run ends on a close of
`conduct-backlog` or of the project's own backlog conductor name. Stories count by their full slug
and conductors by their exact name. A close may name an agent by herdr's name, and a build with no
session log has only `agents.tsv`'s. Both are agent names, cut to 32 characters, with an `s` in
front of a slug that starts with a digit. Such a name counts as the one record whose agent name it
is. The records are the board's stories and those its history deleted, the briefs, `conduct-<epic>`
for each ok `conduct` event, the slugs session logs name, and the targets of `unblock`, `reset`,
`reconcile`, `review` and `kept` events. With no record, or two, the name stays as it is, so two
slugs that share their first 32 characters never merge. A build with no session log under a name
two or more records share may be any of theirs. While it runs, none of those stories waits idle,
and any other story clashes with what each of them touches.

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

When a large epic was split, a block between the two is TSV `split critic_fixed critic_declined
escaped_split_gaps`, one row per split's board PR: the split critic's fixed and declined findings
beside the `split-gap`s logged `--reviewer escaped` against that PR, the gaps it missed. Every
split `board-pr open` recorded in `.swarm/<epic>/split-pr` has a row, a clean one (the critic found
nothing) as `0 0 0`, dated by the day it opened; a split with no record is dated by its first row.
A split is in the window when that day is, and every escaped split-gap counts against it whatever
its own day. `--epic` keeps the splits of that epic or of its `parent:` (read from the board, or
from its last version in the board's git history once the child is gone). The record names a
split's epic; for one with no record `gh` reads the PR's branch (`board/scope-<epic>`), and when gh
fails a note says how many splits it could not place. The split critic's tokens have their own `split-critic` row in `cost`.

Once a row in the window has a review round (`--round` on its findings), two more blocks follow the
rounds. The first is TSV `round reviewer fixed declined nit out-of-scope wrong share_fixed`: per
round, each reviewer and then `all`, the findings fixed, declined in all and by reason, and fixed
over raised as a whole percent. Round `0` is a plan or board PR, and `unknown` holds the rows logged
without a round. The second is TSV `story pr stopped_round why`, one row per story PR with a round
of 1 or more: the round its review stopped in, and why. A final pass that finds nothing logs no
row, so the stop is the review after the PR's last round of findings sent to its builder (the
`tells_findings` of all its builds, whatever their date, plus one), or its last logged round when
that is later. A PR is listed when the window has a row of it with a round, and where it stopped is
read from all its rows, whatever their date. For a merged PR, `pass` means the stop round fixed nothing and `merged-after-fixes`
that it fixed something. A PR that has not merged shows `unmerged`, since its review may still be
going. `--epic` narrows both blocks as it does the others.

The `review_loops` section shows what each review round cost and what it bought, so the stop and
escalation rules can be tuned. It reads `events.tsv`, `findings.tsv` and `agents.tsv`, and calls no
`gh`. Each build of a story (an `ok` `story` line, an `ok` `agent` line for a builder a conductor
started, or an `escalate` build's `ok (attempt N)` with the `story` line after it) is its own loop,
with its own rows; a `merge` line ends its loop, and the lines after it count for none until the next
build starts. A loop is listed when a `review-agent`,
`tell:findings` or `escalate` line of it falls in the window, by local day, and `--epic` keeps that
epic's stories (from `outcomes`). A `review` line counts once for each PR it names, as that PR's
story's (found through `outcomes`, so an epic's review reaches its stories), else as its target's. A
loop's PR is the URL on its `ok` `review` line, else its build's `outcomes` row's (the row of its
builder's latest `agents.tsv` line, as `outcomes` has one row per 7-field line), else `-`. Rounds
count per PR, as findings' `--round` numbers them (the n-th review of a PR is its round n): a build
on a PR starts after the rounds of the builds on it before. Each finding with a `--round` goes to one
loop, the one whose rounds hold its round (the last on its PR takes any later round), so two builds
on one PR never count a finding twice. A finding with no `--round`, or on a PR no loop has, counts
nowhere. Its rounds go in log order: an `ok` `review-agent` opens one, and a review agent started again
before the round closed moves its start; an `ok` `tell:findings`, a `findings-*` step-up (which takes
the tell's place), or the `ok` `review` or `merge` after the last tell closes it. A round no review
agent opened has no minutes.

The first block is TSV `story pr round model minutes fixed declined step_up`, a row per round: the
builder's model (each build start and each step-up takes the next of the builder's `agents.tsv`
lines in a builder role, and a step-up's model is its `to`), the minutes from the review agent's
start to the round's close, the findings fixed and declined given to the loop with that `--round`,
and each step-up in the round as `<trigger>: <from> -> <to> ok`, or `failed` for one that failed
partway, after its builder was closed: a `step-up` or `step-up --resume` whose error says the builder
is closed, but the next did not start (trigger `?`), or a `tell` or `close` whose step-up failed
partway (a tell's has trigger `findings` and closes the round, and a findings step-up resumed after
it goes on that round). A step-up refused before it changed anything (`nothing was closed`) is not
one. A step-up before the first round shows on round 1, ending `before review`; a loop with no round
shows its step-ups on a row whose round is `-`. A PR whose findings name a later round than its
events gets rows up to it. The second block is TSV `story pr rounds end`, for each loop with a round, `rounds` its PR's last
round in that loop:
`held-for-lead` after an `escalated` line; once the PR merged (a `merge` line, or merged in
`outcomes`), `pass` when its last round fixed nothing and `merged-after-fixes` when it fixed
something; else `open`, a PR handed over by `review` and not merged among them. The last is one TSV
row over the loops with a round: the PRs (each once, loops with PR `-` left out), the median and p90
(nearest rank) of their rounds, the minutes spent in round 3 and later (a round with unknown minutes
adds none), the fixes, the share of them found in round 1, round 2, round 3
and later, and on the top rung (`escalate_ladder`'s last model; `-` with no ladder), the builds that
stepped up with their fixes per round up to and after the first step-up, and the failed step-ups.
With no story in the window it prints one line saying so.

The `start_failures` section asks whether a review agent that failed to start was started again.
A failed start is a `review-agent` line in events.tsv whose outcome begins `review-agent:
review-<slug> did not start`, `review-agent: review-<slug>'s start was unclear` or
`review-agent: review-<slug> took its brief`: the agent it opened did not start, may not have, or
took its brief and stopped on an expired login. A refusal before that, such as a bad PR URL or a builder
still at work, is not counted. It prints TSV `day failed restarted_10m
not_restarted`, one row per local day in the window with a failed start. `failed` counts the failed
starts that day. `restarted_10m` counts those followed, later in the log and within 10 minutes, by
an ok `review-agent` line of the same story; each failed start counts on its own, so a story that
failed twice before one ok start can count once each way. `not_restarted` is the rest. After a
blank line, TSV `slug failed_at` lists each failed start not restarted, with its UTC time from the
log. With no failed start in the window, the line `no failed review-agent start in the window`
replaces both. `--epic` does not narrow it.

The `run_times` section shows how long `status`, `next` and `dash` take, from the run-times log
(§ Logs and outcomes). Over the rows whose start falls in the window, by local day, it prints TSV
`command runs median_s p90_s over_60s`: one row per command, in name order, with its runs, the median
and p90 (nearest rank) seconds and the share of runs over 60 seconds. Torn rows count nowhere: one
cut short, a time that does not parse, seconds that are not digits, or a command other than those three. With no log it prints a line saying so, and with no row in
the window another. `--epic` does not narrow it.

The `test_runs` section shows how long local test runs take under load, so a test queue or a `JOBS`
change can be decided from numbers. `scripts/test.sh` appends a line to the main checkout's
`.swarm/test-runs.tsv` as each run starts and as it ends. It finds the file through `git rev-parse
--path-format=absolute --git-common-dir`, so every worktree's runs land in one file, and never
through `SWARM_PROJECT`, which tests run without. A line holds the start and end times (UTC), the
seconds taken, `JOBS`, the filter, the branch, the 1-minute load average and the CPUs, how many other
runs were going, the exit status, and the run's PID. The filter is `all` when the files run are every
`tests/*_test.sh`, else `TESTS`, else how many files (`1 files`), with ` shard i/N` after it for a
`SHARD` run, which is no full run. Each line reads the load, CPUs and other runs at its own moment,
and the start line leaves end, seconds and status empty, so a run that was killed still leaves its
start. A run counts as going while its mark, a file named by its PID in `.swarm/test-runs.d/`, is
there: test.sh writes it at the start and removes it at the end, and a mark whose PID has gone is
removed when the next run counts. A write that fails is skipped and never changes the run's exit
status. A `TEST_RUNS_LOG` that is set names the file instead (empty logs nothing); test.sh sets it
empty for its jobs, so a run a test starts itself logs nothing and is never counted as going.
The section reads the full runs (`all`) whose start falls in the window, by local day, less those
interrupted (a status of 128 or more) and torn lines (one cut short). Each end line pairs with its start line (the same start time and PID), and a run's at_once
is the larger of the two lines' other runs, plus the run itself. It prints TSV `at_once runs
median_s p90_s median_load`: the runs by at_once (1, 2, 3-4 and 5+), each with its median and p90
(nearest rank) seconds and the median load at the start (`-` with no run). After a blank line, TSV
`start seconds branch at_once status` lists the 5 slowest. These two blocks are the baseline for
full runs. After another blank line, TSV `builder_runs median_s p90_s` counts the runs on `story/*`
branches whose start falls in the window, of any filter. A `TESTS` run, an `N files` run and a full
run count; a shard run, an interrupted run and a torn line (one cut short) do not. It gives the count
and the median and p90 (nearest rank) seconds, `-` with none. With no log, as in a project with no
`scripts/test.sh`, it prints nothing. With no full run in the window, a line that says so takes the
place of the first two blocks. `--epic` does not narrow it.

## The outer loop

Each finding that review fixed is logged with
`swarm.sh log-finding --reviewer <who> <kind> <PR> "<one line>"`, where the kind names the class of mistake
(`vacuous-test`, `denylist`) and `<who>` is the reviewer that raised it: `codex`, `fallback` (the agent codex-review starts in codex's place on a usage limit), `code-review`, `ci` (a
PR review bot, a check-run note or a code-scanning alert), `conductor` or `lead`, or `skeptic` and `critic` for a plan review's finding on a board PR, and `split-critic` for the check on a large epic's split (commands/plan-epic.md step 0). A defect that a later fix finds in merged work is logged against the original PR with `log-finding --reviewer escaped <kind> <original PR>`. Its outcome is `escaped`: it counts toward the `recurring` block, but `outcomes` and flow's `reviewers` leave it out, since review missed it. Each finding declined is logged with `log-finding --declined <reason> --reviewer <who>`, where the
reason is `out-of-scope` (outside the story's touches and **Done when**), `nit` or `wrong`, and the row keeps it as a seventh field; `outcomes` counts fixed and declined apart, and its
`recurring` block counts the fixed and escaped ones, never the declined. `--round <n>` records the
review round a finding came from: the n-th review of a story PR is round n, the passing one included,
and a plan or board PR is round 0. The review agent and the conductor pass it on each finding they log, and flow's `reviewers` counts each round's yield from it. When a conductor finishes,
`/swarm-dev:swarm` files one story with `checks: <kind>` for each recurring kind that has no check
yet, in a board PR named `check-<kind>` (written in place when the board is outside the repo, and
noted in `.swarm/checks-filed.tsv` so the kind is filed once). The
story adds a test, lint rule, hook or review-prompt line that catches the kind, since a rule pasted
into a prompt does not stop the mistake by itself. While that PR is open, once it has merged, or for
90 days after you close it unmerged, the kind gets no new story. Once the
check merges, `outcomes` shows whether the kind came back less often, and `/swarm-dev:swarm` tells
you when its fixes after the merge reach 3 PRs. The log is `.swarm/findings.tsv`, local to
the machine: date, kind, PR, the line, its outcome (`fixed`, `declined` or `escaped`; rows written before the
outcome column count as fixed) and the reviewer (`unknown` when a row was logged without `--reviewer`
or before that column existed), then a declined row's reason and, with `--round`, the round (after an
empty reason on a fixed row). A row with no round is round unknown. Columns added later go on the end,
so readers ignore any they do not know.

**Green means more than green checks.** A check can pass and still carry a failure note (a
code scanner often does), so the lead also triages `swarm.sh findings <repo> <pr>`: the notes on
every check run of the PR's head, and its open code-scanning alerts (the first 100 of each). Each is fixed, or rebutted in
the PR with a reason; none is silenced or dismissed. findings also reads the PR's diff and body. A
test the diff adds (Go `func TestX`, Python `def test_x`, a `check` line in `tests/*_test.sh`, a JS
`it(` or `test(`) needs a line in the body with FAIL and its name, which the builder pastes from the
mutation run. findings prints each test without one as `rules-unchecked`, with the command that
logs it, `log-finding --reviewer ci`. A moved test is skipped: an added test line that matches a test
line the same diff removes, from another file or elsewhere in the same one, with leading and
trailing whitespace ignored. A removed line counts only where an added one would: in a test file,
outside a heredoc. Each removed line covers one added line, so a test added beside a moved one
still needs its FAIL line.

## Commands

| Command | What it does |
|---|---|
| `swarm.sh where <agent>` | Print where one of this project's agents is: its pane id, its workspace's label and its tab's label, as `<agent>: pane <pane>, workspace <label>, tab <label>`. The workspace label is `-` when herdr gives none: the workspace has no label, or herdr could not list them. A tab herdr gives no label for, or whose list herdr could not give, shows the name swarm-dev gave the tab (its tab record's), as `status` and `dash` do. `<agent>` is a story's slug, `review-<slug>`, `conduct-<epic>` or a herdr agent name. herdr lists every project's agents, and two can share a name, so only an agent in a pane this project opened counts. When herdr lists no such agent there, it says so and exits 1. |
| `swarm.sh swarms` | Print every swarm herdr runs on the machine. For each workspace labelled `swarm-lead · <label>` it prints `<label>  <dir>`, then a line per workspace of that project, the lead's first: `<workspace label>: <agent>, ...`, or `no agents`. An agent herdr gives no name shows as `<pane id> (no name)`. An agent's state is left out: herdr's word for it is not its session's, and the sessions are other projects'. The lead's dir is its first pane's. Each pane counts as in the nearest folder at or above its own that has `.claude/swarm/config`. A pane in a story worktree (`<dir>-wt/<slug>`, or a folder in it) counts as in `<dir>` when `<dir>` has that config. A pane in another repo's worktree (a `-wt` folder with no swarm config) is skipped. A workspace's dir is its first pane's, as conductors find their own workspace. Another workspace is the project's when its dir is the lead's, or is a project whose last `board_dir` holds the lead's dir (a board kept outside the repo), or when the project's `.swarm/lead/agents-workspace` record holds the workspace's id and label, as for a lead-agents workspace whose panes are all in other repos' worktrees. That record is read from each project some pane is in. A lead that runs in a board outside the repo, with no pane open in the project itself, leaves nothing that names the project, so its lead-agents workspace is left out until a pane opens there. Its label must also start `<part> · `, where `<part>` is the lead's label, the folder's name, or the folder's name with that folder's own path hash. So `app-2 · e1` never lands under `app`, and two folders called `app` keep their own workspaces. A workspace no lead owns is left out, and so is one an older swarm.sh labelled without ` · ` (a bare `backlog` or `<epic>`). With no lead workspace it says so. It reads herdr's workspace, pane and agent lists once each, each cut after 30 s (`SWARM_REPORT_SECONDS`), and exits 1 naming the list when herdr cannot give one in time. |
| `swarm.sh log-finding [--declined <reason> \| --filed] [--reviewer <who>] [--round <n>] <kind> <PR URL> <text>` | Log a review finding by kind. `--round <n>` records the review round it came from (0 for a plan or board PR). `--declined <reason>` records one that was declined (`out-of-scope`, `nit` or `wrong`). `--filed` records that the lead filed a declined out-of-scope finding as a story, so `swarm.sh next` stops offering it; no report counts a filed row. The reviewer is codex, fallback, code-review, ci, conductor, lead, skeptic, critic, split-critic (the check on a large epic's split), or escaped for a defect found after its PR merged; a gap in a split that a later plan or build finds is logged `--reviewer escaped split-gap` against the split's board PR. |
| `swarm.sh intervene <kind> <cause> "<one line>"` | Log a time a person had to step in: `lead-hand` (the lead acted by hand where a command should have) or `user-caught` (the user found a problem first), and why, a cause from `INTERVENE_CAUSES` in `bin/swarm.sh`. It writes one `incident` line with the field `cause=<cause>`, which `flow`'s `incidents` section and dash's interventions light count. An unknown cause fails and lists the causes. |
| `swarm.sh outcomes` | One row per build: model, cost and tokens by type, review rounds and other tells, its epic, whether its PR and its story merged and when, findings fixed and declined by reviewer, when it started, why it was last closed, its escalation steps, and minutes from start to PR and from PR to merge. Once a story is finished (its file is off the board, every PR is merged or closed, and every check on them has finished), its PRs are read from gh once and kept in `.swarm/outcomes-prs.tsv`. `flow` and dash's ci line then read them from there instead of asking GraphQL on every run; `dataset` reads them there too, but still lists each merged story's PRs with gh itself. The cache is keyed by the story's newest build, so a rebuild reads gh again. A cache that cannot be written is said on stderr and the report still prints. |
| `swarm.sh dataset` | Write `.swarm/dataset.jsonl`, one JSON line per merged story. Each line holds the story as the board PR merged it (text, kind, risk, touches, `depends_on`, `estimate_lines`, `easy` and the planner's model), and what happened: diff lines and files of its newest merged PR (the story and epic files left out), builds, findings rounds, fixed findings, rework within 7 days on any of its PRs (`outcomes`' rework column, which flow's `model_fit` reads too; null when `outcomes` could not judge one of its PRs, or one merged in the last 7 days), cost, minutes from start to merge, every model that built it and each escalation with its trigger. `was_easy` is true when the story merged on its first build with at most one findings round, no rework and a diff under 100 lines (`was_easy_rule: 1`), and null when an unknown diff or rework is all that could decide it. Nothing from the environment or the transcripts goes in. A story whose repo cannot be found, or whose PRs `gh` cannot read, is skipped and keeps its line from the last run, and so does any story the run does not read, so the file never loses a story. When `gh` itself is down (`gh auth status` fails) or the logs cannot be read, it stops and leaves the file as it was. |
| `swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>] [--no-cache]` | The project's numbers, a section each: `ci_health` (median CI minutes per PR head, red runs per PR and flakes, and the test files that failed in a rerun that went green), `cost` (where the tokens went, with a row for the lead's own sessions, then the tokens on each ladder rung per step-up with how its build ended, and the share of builds that reached each rung), `epic_totals` (each epic's cost, start-to-PR and PR-to-merge minutes, and the share of its PRs that needed main merged in, beside the 55% baseline), `features` (each feature in `docs/features.tsv` against its metric and baseline, with the ones nobody uses or measures flagged for deletion), `gh_calls` (gh runs per hour by agent role and by subcommand, GraphQL and REST apart, with the paginated and watching runs that spend many requests, and each hour's share of the 5000, from the gh shim's `.swarm/gh-calls.tsv`), `holds` (one row per hold of a ready story: its epic, the first hold's reason and the minutes until its next build started, or how it ended with no build (`dropped`, or `removed` once its story file left the board), or `open`; then the built holds' minutes per reason class, `clash` when the reason names a PR or a hyphenated story that had started by then, `other` for anything else, give-up, closed this wave and `not held:` included), `idle_slots` (per epic, the minutes a story sat ready with no build and nothing it clashed with running, while its conductor ran and while none did, and the most ready at once), `incidents` (incident lines per day and kind, then API-error and auto-mode stops per epic, incidents per kind and cause, the stalled incidents with their bg, test and sign inputs, and the count of false stalls), `lead_queue` (per day, the median and longest wait on the lead, and what still waits: held, escalated and kept stories, and PRs waiting for a merge; a kept story waits from its `kept` line until it is reviewed, closed with `--drop`, finished, dropped or reconciled, and dash names `swarm.sh review` and `close --drop` on its row; below it, when the window has any, a table of no-agent items: a started story with no agent (`no-agent`), a failed step-up (`step-up-failed`) and a review agent that never started (`no-review`). Each runs to its `lead-woken` line from the newest close of the story's builder or review agent, or, with no close since its last start, from the first `no-agent` line or failed start. A `step-up:failed` line, a review agent's failed start and a `review` or `kept` line restart the clock, and a failed start while the builder still runs starts it only when nothing waits, and never opens an item. An ok start, an ok tell, a hold, an ok `upgrade` of the story's epic (but not for a failed step-up) and a reconcile that reopens the story end the wait unmeasured. Per day it gives the median and longest minutes (`-` when no item entered that day, though a wake did), the items not yet woken (open only while the story is ready) and `woken_while_working`: no-agent wakes for a story whose builder had started with no close or `step-up:failed` line since. A builder whose pane died without a close line looks the same in `events.tsv`, so a nonzero count is either an alert while the builder was working or a real alert for a pane that went with no close; the story's events and herdr show which. A failed review-agent start wakes the lead as `ok (no-review)` while its builder is listed, and as `ok (no-agent)` when the builder is gone too, since that poll prints the `no-agent:` line. Last, after a blank line, one row over the per-day table's items in the window, never the no-agent ones: `items`, `median_min`, `p90_min` (by nearest rank) and `max_min`, with `-` in each column when there is none), `merge_ins` (why PRs merged main in: a conflict, a clean merge while behind, or neither, with the files conflicts hit most), `merges` (the stories finished per day, which dash's speedometer shows, then merge's holds per day by kind), `model_fit` (cost against results per model and story class, and builder subagents' share of build cost), `predictions` (per planner model, the precision and recall of `easy` against `was_easy`, and how many lines its size estimates were off by, from `.swarm/dataset.jsonl`), `review_loops` (per story PR, each review round's builder model, minutes, findings fixed and declined and step-up, how its loop ended, and totals for tuning the stop and escalation rules), `reviewers` (findings each reviewer raised per kind, fixed or declined, the split critic's fixes beside the split-gaps it missed per split, review rounds per PR, and once findings carry `--round`, each round's yield and the round each story's review stopped in; `--epic` counts only that epic's PRs and lists them), `run_times` (per command, how many `status`, `next` and `dash` runs, their median and p90 seconds and the share over 60 seconds, from `.swarm/run-times.tsv`), `start_failures` (per day, the review agents that did not start, how many of them an ok start of the same story followed within 10 minutes and how many it did not, then each one not restarted), `test_runs` (local `scripts/test.sh` full runs by how many ran at once, the larger of the count at the start and at the end, with the median and p90 seconds and the median load at the start, and the 5 slowest; then builders' runs on `story/*` branches of every filter, with their median and p90 seconds; from `.swarm/test-runs.tsv`), `throughput` (builders at once, stories per chain, review wait and stacked starts, per epic) and `time_in_state` (hours per epic in each state: held ready before a build, building, CI, review wait, fixing and merge wait, with each one's share, largest first, then the median and p90 minutes from a story going ready to its build starting, and from a PR going green, or opening if later, to its next review round starting). |

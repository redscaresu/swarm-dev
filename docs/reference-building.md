# Reference: Building

Part of [the reference](reference.md), which lists every section and the file that holds it.

## Building

`swarm.sh conduct <epic>` starts a fresh conductor that drives the epic's stories to merge, then
stops and reports; the session it was started from stays free. Its last act is writing that report
to `.swarm/conduct-<epic>.report.md`, and that file, not the agent going idle, is how
`/swarm-dev:swarm` knows it has finished: a conductor is idle whenever it waits on its own
background work. When it starts, an epic still `later` is set `active` (in
`.swarm/board-state/epics/<slug>`, which `conduct` reports in one line), so `status` and `next`
stop listing it as waiting on you. It runs in a herdr workspace labelled for its project and the epic's `parent:` if it has one (epics with the same
parent share it), or else for the epic (see **Workspace labels** below), in a tab named for the epic, in a pane named `conductor`. Each story it starts gets a pane in
that tab, named for the story; a tab holds four panes, and the fifth opens `<epic>-2`. A pane
opens in the workspace of the agent that starts it. One the lead starts opens in
`<project> · lead-agents`, except a conductor, which opens in its epic's. A tab whose panes are in
another workspace counts as full, so that pane opens `<epic>-2` there instead. A one-off
story gets a tab of its own. Conductors of different epics can run side by side (each watches only its own epic's PRs, with
`watch --epic`, and a fix-main story's, which a conductor builds first when the lead's note asks), as long as their stories touch different files; shared files are the lead's alone.

**A built epic.** An active epic is built when all its stories have left the board: no story file
names it, and either a deletion of one is not committed yet, or the board's history passes two reads:
a story under the epic's slug finished at some time (deleted by its merge), and a story naming the
epic was deleted, by a merge or a board-only drop, since the epic's file was last added (a file HEAD
has). So a new epic that takes a finished epic's slug is planned, until a story of its own is dropped
from the board, when it reads as built. Its file stays until its conductor's Finish PR deletes it.
`next` never plans a built epic again. While its report is missing, or older than the newest commit
that deleted one of its stories, `next` prints `conduct <epic>`, after the `stage` step and before
`plan-epic`; the why says the epic is built and whether its report is missing or stale. The conductor
that step starts has no agent work left, so it writes its report and Finish PR at once. Once the
report is newer than that commit, the epic gets no step. On a board with no git history (not in git,
or no commit yet) no epic reads as built, so an active epic with no stories is still planned
there.

**The backlog conductor.** `swarm.sh conduct --backlog` starts `conduct-backlog-<dir>-<hash>` (the
first 9 characters of the project directory's name, then 6 hex characters of a checksum of its path), which builds the ready stories with no `epic:` (the one-offs) the way an epic's conductor builds an epic: waves with
`story --strict`, and a review agent per PR, which hands it over or merges it the same way. It runs in its project's
`<project> · backlog` workspace and needs no epic file; a board with an `epics/backlog.md` makes it refuse. herdr's agent
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

Conductors also start on their own, the backlog's and an epic's alike: after `swarm.sh merge
--board` lands, once it has sent its notes (a conductor's own board merge included), and from
`swarm.sh next` when its step is `wait <conductor>`. For each active epic with a ready story an agent
builds (`kind` code, docs or chore) and no conductor running, it runs `swarm.sh conduct <epic>`; for
such stories with no epic, `swarm.sh conduct --backlog`. A conductor still in its pane counts as
running. When it has written its report, it prints `no conductor started: <conductor> has reported;
collect it first`: a new start would delete that report before the lead reads it. A conductor whose
pane is gone (closed by hand, a herdr restart, a crash) and whose report nobody collected (no `close`
of it in `events.tsv` since the report, as collect's `swarm.sh close` logs) gets `no conductor started:
<conductor> is gone, and nobody collected <report>; read it, then delete it`. When another
project's agent holds the conductor's name, it says so and starts none. While a conductor works, `next` prints `also: lead <slug> blocks <slugs>` after the wait's why. It names each story that a blocked story an agent builds depends on, when no agent builds the named story: a ready story of a kind no agent builds (a `lead` story), or such a story that is blocked with no `depends_on` (only the lead can ready it). A story of a kind an agent builds, blocked with no `depends_on`, gets no `also:` line, because `finish` would close it unbuilt. A story in a draft or `later` epic gets none, and neither does one with `after:`. `status` reads a blocked story's line, of any kind, as `blocked: <slug> (by <parents>, which no agent builds)` when every open parent is work no agent builds. That is a story of a kind no agent builds (in any status), a story blocked with no `depends_on`, or a hand step such as `operator:<x>`. With an open parent an agent builds, or an open epic, it reads `blocked: <slug> (by <parents>)`. A draft, `later` or `split` epic's stories start nothing, and
neither does a `fix-main-*` story, which every running conductor builds first. No conductor starts
for an epic or the backlog, and it says why, while that conductor's report is newer than every story
and epic file, and than the state files swarm.sh keeps in `.swarm/board-state` for that epic and its
ready stories (an `unblock` or a `reset` readies a story there): a new one would stop as the last did.
Another epic's state writes do not count. Nor does a backlog conductor start while its report
lists a one-off whose worktree is still there under `not started:` (the stops above). Nothing starts
while a working conductor has stopped on an expired login or an API error, which would stop a new one
too, or while herdr cannot list its agents, since what runs is then not known; each prints why. From
`swarm.sh next`, nothing starts once a read it needs was cut at next's deadline, since a cut read could
hide a stopped conductor: it prints `no conductor started: <conductor>: a read it needs was cut at the
report's deadline; run swarm.sh next again` for each one it would have started.
Under `merge = agent`, none starts without an allow rule for `swarm.sh merge` (§ Merging, the conduct
preflight).
Outside herdr it starts nothing and prints the `swarm.sh conduct` to run. Each start prints `started:
<conductor> (swarm.sh conduct <arg>)`, which `next` puts after the wait's why, so its first line is
still the step, and logs a `conduct` line in `events.tsv` as `swarm.sh conduct` does. A start that
fails prints a warning, logs its error as that line's outcome, and changes neither command's exit
status. The warning says to run the `swarm.sh conduct` yourself, or, when an agent's own board merge
started it with only that agent's environment, that the lead's `swarm.sh next` starts it. `dash --check` and `/epic` read next's step with `swarm.sh _step`, which starts nothing.

**Workspace labels.** herdr's workspaces span every project on the machine, so each label swarm.sh
gives one carries the project's label, joined to the rest by ` · `:

- `swarm-lead · <project>`: the lead's own workspace, and the tab the lead's session runs in.
- `<project> · <epic>`: an epic's conductor, its stories' builders and their review agents. For a
  child epic of a split one, `<epic>` is its `parent:`, so the children share the workspace.
- `<project> · backlog`: the backlog conductor and the one-offs it builds.
- `<project> · lead-agents`: every agent the lead starts itself, such as the HLD co-author, a
  planner or a builder it restarts. Its first agent makes the workspace, and swarm.sh keeps its id
  and label in `.swarm/lead/agents-workspace`, so the workspace is reused while herdr lists it under
  that label, even once its panes are all in other repos' worktrees, whose paths say nothing about
  whose they are; one relabelled is left alone, and a new one made. An agent started outside the
  project, as from a board kept outside the repo, keeps a pane at the project directory ahead of its
  own, so the workspace stays the project's while that pane is open. When herdr gives no list, no
  workspace or no such pane within a few seconds, the agent opens in the lead's own workspace, and
  swarm.sh says so. Two first agents started at once share one workspace: the record is made under a
  lock, and the second waits for the first's. A conductor still opens in its epic's workspace, and
  `conduct` refuses an epic named `lead-agents`, or with that `parent:`, as it refuses one named
  `backlog`.

`<project>` is the project directory's name. When herdr already lists a workspace labelled
`<that name> · ...` for another directory, it is the name, a dash and 6 hex characters of a checksum
of the project's path (the hash the backlog conductor's name ends with), so `/a/app` gets `app`
and `/b/app` gets `app-<hash>`. herdr gives a workspace no directory of its own, so a workspace's
directory is that of its first pane in `herdr pane list`: the conductor's or a review agent's, and
in `<project> · lead-agents` a lead agent's, or the pane at the project directory swarm.sh keeps
ahead of a lead agent started outside the project. A
builder's pane in the project's own story worktree (`<project>-wt/<slug>`) counts as the project's;
one in any other repo's (`<repo>-wt/<slug>`) is skipped, since its path does not say whose it is. `conduct` takes a
workspace only when its directory is the project's: one under either form of the project's label, or
one under the bare `<epic>` or `backlog` label an older swarm.sh gave with no other project's pane in
it, so a conductor started before the upgrade keeps its workspace and never takes one another project
shares. Otherwise it makes a new one. A tab record that still lists a live pane in a workspace an
older swarm.sh shared counts as full (see above), so the conductor, its builders and its review
agents open a new tab in the project's own workspace. Labels can still repeat, for example: two
projects of one name that start a conductor at the same moment both make `<name> · <epic>`; a
project inside a folder whose name ends in `-wt` is skipped like a story worktree, so another
project of its name takes the plain label too; and a project's workspace with only its builders
left (in `<project>-wt/<slug>`) has no directory for another project, which makes the plain label
as well. Each still reuses only its own workspace. A workspace left with only other repos' builders
has no directory, so the next conductor makes a second one.
`close` and `tidy` find tabs and panes from `.swarm/state`, not from labels, so a relabelled
workspace closes as before.

The first `swarm.sh` command the lead runs in a workspace, once the project is set up, labels that
workspace and its tab (`herdr workspace rename`, `herdr tab rename`) and adds the workspace's id to
`.swarm/lead/workspace`, one line per workspace. The `init` that sets the project up comes before
there is a lead, and `version` and `update` run before swarm.sh looks for a project, so none of the
three labels anything. A later command from any workspace listed there
sends herdr nothing, so a lead that moves to another workspace and back has only the new one
labelled. Each time it labels one, it drops from the record any workspace herdr no longer lists, and
any lead workspace herdr lists with another label; a refused or kept workspace stays recorded while
herdr lists it. Each herdr call it makes is cut off after `SWARM_LEAD_HERDR_WAIT` seconds (default
5). This check runs before the command's own work, outside the deadline `status` and `next` give
their reads: the lead's first `status` or `next` in a workspace can take up to 20 seconds more by
default (four herdr calls), and while herdr hangs on its list, each command from that workspace
waits up to 5 seconds for it. When herdr gives no workspace list, or one without the lead's
workspace (herdr restarting), or a call is cut off, nothing is recorded and the next command tries
again. When herdr refuses a rename, swarm.sh says so once, on stderr, naming the workspace or the
tab alone, and records it, so it does not try again there; the message names
`.swarm/lead/workspace`, which you delete to try again. A lead opened in a workspace swarm.sh
labelled for a conductor or its agents (`<project> · <label>`, or an older swarm.sh's bare `backlog`
or `<epic>`) leaves it that label, says so once and records it as `kept`, so the next `conduct`
still finds it. The same goes for a workspace another project's lead labelled, `swarm-lead · <name>`
with a directory in neither this project nor its board: its label stays, so the other lead's record
stays true. The lead's `<project>` also gets
the hash when herdr lists another lead's `swarm-lead · <that name>` workspace: one the record does
not hold with that label and whose directory is neither in the project nor in its board, so the
second lead of one name gets a label of its own and the lead's own workspaces never count. Two
first commands at the same moment both send
the rename; a record line is lost only when their writes land at the same instant, and that
workspace's next command labels it again. swarm.sh tells the lead the way the plugin's Stop hook
does: a session with no agent's environment (no `SWARM_AGENT` or `SWARM_GH_CALLER`), in a swarm
project, from a folder that is not a worktree. A lead whose folder is in no project, such as a board
kept outside the repo, belongs to the project `SWARM_PROJECT` names. Nothing is renamed from an
agent's pane, outside herdr, without herdr's socket (`HERDR_SOCKET_PATH`), by a `swarm.sh` another
one runs (`dash --project` runs one for each project it draws), by a command run from one project's
folder for another (`SWARM_PROJECT`), by a test hook (a command starting `_`), or by a command whose
stderr goes to `/dev/null`, as the Stop hook's do, since a refusal said there would be lost.

**`next`'s idle dependency line.** After its step, `next` prints `idle: <story> waits on <dep> but
shares no touches part with it and needs nothing from it` for each blocked story an agent builds,
with no `held_by:`, whose `depends_on` story an agent builds too and is neither done nor in review.
Both must have `touches`. It compares them by part, as `story --strict` does: two entries share a
part when they name the same file and the same first word of the part (past a leading `§`, `#`,
"the", "a" or "an"), or both name the bare file. Another part of the same file shares nothing. The
line stays quiet when a word of the story's `needs:` line is the dependency's slug, so
`needs: <dep> (its --flag)` keeps a dependency the check calls over-broad. The lead
either drops the dependency or names it in `needs:` (step 1 of `/swarm-dev:swarm`).

**`next`'s idle ready line.** `next` also prints `idle: <story> is ready with no build, exit: <exit>`
for a story it would build (`status: ready`, a kind an agent builds, no `held_by:`, and no epic or an
active one) whose build has not started and that has been ready for `queue_minutes`. A build has
started when the story's worktree exists, or an ok `story <slug>` line in events.tsv is no older than
its ready time. A `story/<slug>` branch left with no worktree also silences the line, since
`swarm.sh story` refuses to build over it. The ready time is the newest of the story file's mtime, its board-state file's mtime
and its ok `unblock`, `reset`, `reset:held`, `reconcile` and `close` lines. A later edit restarts the
clock, so the line errs towards silence. The story must also share no `touches` part (by the rule
above) with a running build: a story in review, or one whose build has started (a held stacked
story keeps its worktree). A story it
depends on, or one that depends on it, does not count, since a stacked story starts on its parent's
branch. The exit is `swarm.sh tell <conductor> note <file>` while the story's conductor runs (the
epic's, or the backlog's for a story with no epic). It runs from an ok `conduct` line until a close
of its agent or a `report` line, and not while its report file is there (`conduct` removes the last
one before it starts). With none running the exit is
`swarm.sh story --strict <slug>`, which refuses a clash with a builder herdr lists. The check reads the board, its state, events.tsv and
one git read of the `story/*` branches per checkout that has a story that would get the line, with no
gh or herdr call. A git read that takes more than 5 seconds counts every branch as there and ends git
reads for that run, so the check stays quiet and waits on git at most once.
Because it never asks herdr, a conductor that went with none of those lines and no report (herdr
restarted, it crashed, or its pane was closed by hand) still counts as running. The line then keeps
naming its note, which nobody reads. When a note gets no answer, check the conductor with
`swarm.sh status`: `swarm.sh next` starts a conductor for ready work that has none, or you can run
`swarm.sh story --strict <slug>` yourself.

**`next`'s idle epic lines.** `next` prints `idle: epic <epic> can start, exit: <exit>` for a draft
or later epic in the current stage that has nothing left to wait on. The current stage is the lowest `stage:` an epic on the board carries, whatever its status. An
epic with no `stage:` is in it, so when no epic carries one, every epic is. An epic whose `stage:` is
not `v<x.y.z>` gets no line. Nothing is left to wait on when the epic's `depends_on` lists something
and every item it lists has left the board or is `done`, or when one of the epic's stories that an
agent builds is `ready`. An active epic whose only open stories are lead `after:` ones counts as done
here, as it does wherever `next` reads a dependency. A later epic with no `depends_on` and no such
ready story waits only on the user, so it gets no line. Nor does an epic with `parent:` set (a split's
children are the user's), one with `unasked_plan:` set (the gate already shows its plan or the user's
decline), or a staged draft (`next`'s `stage` step sets it active once the tag before its stage is
cut, and the gate lists it until then). The epic the step `next` takes names (`plan-epic <epic>`) gets none
either: the lines are for capacity no step uses. `next`, `status` and `dash` drop that epic's line;
`wait --lead` takes no step, so it prints every such epic's line. The exit is the epic's case: `tell
the user it can start (/swarm-dev:epic <epic>)` for a draft, which nothing plans and only the user
agrees (or, staged under an HLD that grants `epics`, the `stage` step sets active);
`swarm.sh plan-unasked <epic>, then /swarm-dev:plan-epic <epic>` for a later epic with no stories
and its `depends_on` done, planned unasked as the `plan-epic` step does; and `the user's go, then
set it active with agreed: <today> in a board PR` for a later epic whose stories are on the board,
as `/epic` does. `next` also prints `idle: epic <epic>
has no plan running, exit: /swarm-dev:plan-epic <epic>` for an active epic with no stories and
nothing in its `depends_on` holding up its planning, and not built (**A built epic**, above), as the `plan-epic` step judges it, that the step
`next` takes does not name, while no plan of it runs: no `scope-<epic>` tab record (or numbered
`scope-<epic>-<n>` one) in `.swarm/state`, and no open plan board PR (its `_board-scope-<epic>`
worktree). A plan's
record goes when its panes close, so a plan that stopped with no stories and no PR brings the line
back. A lead story whose `after:` names its epic does not count as one of the epic's stories. An epic
that a rerun of an interrupted `/plan-hld` will overwrite gets no line, as `next` leaves it to that
rerun. Both lines come from the predicates `next`'s steps use, so they read what those read: the
board, `.swarm/state`, the board PR worktrees and, for an active epic with no open story, the board's
history.

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

`agent_env = NAME ...` in `.claude/swarm/config` adds names for every agent of every role: the HLD
and epic co-authors, planners, conductors, builders and review agents. A restart keeps the names.
`swarm.sh upgrade` gives them the values of the session that runs it. When herdr restores a pane, the
values come from that pane's new shell, since swarm.sh never writes a value to disk. So a key you
export only in the session that started the agent is gone after a herdr restore; export it from your
shell's startup files to keep it there. This is how a provider's key
reaches agents. On Azure Foundry, for example, Claude Code needs `ANTHROPIC_FOUNDRY_RESOURCE` and
`ANTHROPIC_FOUNDRY_API_KEY`, and the `ANTHROPIC_DEFAULT_*_MODEL` names if your deployments are named
differently from the models. Without them every agent stops at its start. Each value comes from the
session that starts the agent. A name that session does not have is skipped with a warning, so the
same board still runs from a session without the provider. When the config loads, `swarm.sh` refuses
a name that is not `[A-Z_][A-Z0-9_]*` or is reserved, by the same rules as `env:`, and names the line.

By default, a login read from the environment does not reach an agent either: `ANTHROPIC_API_KEY`,
`CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, or a `GH_TOKEN` for `gh`. A story can name
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY` or `GH_TOKEN` for its builder (never a `CLAUDE_CODE_*` one).
Agents with no story of their own (planners and review agents, and conductors beyond their stories'
names) get one only when `agent_env` names it, and then every agent gets it. Otherwise, log in
through each tool instead: `claude` then `/login`, `codex login`, and `gh auth login`. On Foundry, Bedrock or Vertex, the provider and model
selection above passes from the session that runs swarm.sh, or can go under `env` in
`~/.claude/settings.json`, which every Claude Code session reads. The credentials come from the
provider's own login or profile files (`aws sso login` or a profile in `~/.aws`,
`gcloud auth application-default login`). An exported secret such as `AWS_SECRET_ACCESS_KEY`
reaches agents only when `agent_env` names it. Foundry is the exception: its endpoint and key exist
only in the environment, so when `CLAUDE_CODE_USE_FOUNDRY` is `1` or `true`, every agent also gets
the session's `ANTHROPIC_FOUNDRY_*` and `ANTHROPIC_DEFAULT_*_MODEL` variables, with no `agent_env` line.

Because `SHELL` is zsh and `ZDOTDIR` is empty, every shell an agent starts later, such as Claude
Code's Bash tool and codex's commands, reads none of your `~/.zshenv`, `~/.zprofile`, `~/.zshrc`,
`~/.zlogin`, `~/.bashrc` or `~/.bash_profile`, even when your own shell is bash. Only the system
files in `/etc` (`zshenv`, `zprofile`, `zshrc`, `zlogin`) still run, and a login shell's `PATH` is
put back as it was given after them.

**Board state.** swarm.sh keeps the front-matter keys it writes (`status`, `prs`, `attempts`, `kind`,
`escalated_from`, `held_for`, `held_by`, `kept` and `protected`) out of tracked story and epic files. `review`, `unblock`,
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
reconcile pulled that commit or you did: the file is in neither `HEAD` nor the main checkout. A story
there still in review whose PR gh cannot read, or whose builder's pane could not be closed, keeps its
state until a later reconcile can finish it (§ Merging). When gh can never read that PR (its repo
deleted or renamed, a bad URL), reconcile says so each time: remove
`.swarm/board-state/stories/<slug>`, and `.swarm/escalated/<slug>` if it is there, by hand. A file removed only by hand, or never committed, keeps its state.
A person can still edit a tracked story file in the main checkout, for example to add a **From review**
item. On a board in the repo, a builder reads its story from its worktree, which starts from
`origin/<base>`, so it would never see that edit. `swarm.sh story` therefore refuses a story whose file
there has an edit `origin/<base>` lacks, uncommitted (staged or not) or in a local commit. It refuses
before any worktree or branch exists, and names the file. Land the edit with `swarm.sh board-pr` (or
push it), then start the story again. The check merges the main checkout's copy into origin's, from
their merge base. A main checkout that is only behind origin passes. An edit origin already has
passes too, even under another commit with later changes. So does an edit to only the keys above,
which an older swarm.sh wrote into the file. A story in a sibling repo or an untracked one (`fix_main`'s) is not
checked, since its builder reads the board's own copy.

**Pick the wave.** Only `ready` stories that do not clash. Two stories clash only when their
`touches` name the same file in the same repo and the same first word of a part (`file:part`), or when both name
the bare file. A bare file does not clash with a part of it. A part's first word skips a leading `§`, `#`, "the", "a" or "an". Otherwise both build at once, even in the same file: git merges edits to
different parts of one file, and a story names the functions it changes. A builder whose PR
conflicts with its base merges its base in, resolves it, reruns the tests and pushes; a conflict
never sends a story back to `ready`. The conductor sends that as a `nudge` tell, which is not a
review round, and starts a builder in the story's worktree when the one it had was closed after
`swarm.sh review`. The conductor sends every nudge its brief names as
`swarm.sh wait --stall --idle <slug> && swarm.sh tell <slug> nudge <file>`, run in the background,
and the lead every nudge to a builder that `/swarm-dev:swarm` names as
`swarm.sh wait --idle <slug> && swarm.sh tell <slug> nudge <file>`, without `--stall`, so its wait never
logs a stall or steps up a build a conductor owns. On a builder's wait (not a conductor's or a review
agent's), `wait --idle` exits 0 only when it prints `idle` or `done`, once the builder's turn is over. Where a plain `wait` would exit 0 on anything else (`auth`,
`waiting`, `gone`, `stepped up:` or `stepping up:`), it exits 5. So the tell never reaches a builder at
work, and a wait that times out, stalls, steps the build up or prints `stuck:` sends nothing. The
sender deals with what the wait printed and sends the nudge again the same way. The conductor's wait
is its one wait on that builder.
Work that edits a shared file (`AGENTS.md`, root config, schemas, hygiene scripts) is done by the
lead, alone.

A wave only sees its own epic, so `story` also looks across epics. Before it makes anything, it
compares the story's `touches` with those of every story in another epic (a story with no epic
counts as another). If one of them is open (in review, or `ready` with its builder open) and touches the
same part (by its first word) of a file, or both name the bare file, `story` prints `warning: <other> (epic <e>) is open and touches <entry>;
start <slug> after it merges` and starts the story anyway. `story --strict` refuses instead, naming
the other story, and leaves no branch, worktree, pane or brief behind. It also refuses when herdr
cannot list its agents or the board's `touches` cannot be read, where plain `story` warns that it
cannot tell. Then nothing is known to be open, so the message says to retry the story, not to wait
for a merge. `--strict` may come before or after the slug. Conductors always pass
`--strict`.

A `<file>:<part>` entry matches an entry in the same file whose part has the same first word, past a
leading `§`, `#`, "the", "a" or "an" (so `docs/method.md:§ Building` matches `docs/method.md:Building`), and a
file-only entry matches only another file-only entry for that file. An entry with no `/` or `.` before its `:` names a fn in the previous entry's file and
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
its PR is. The child's review agent, which ran that review, stops there, and the child's builder
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
A codex agent, or one with no recorded session, is waited on through herdr's status. `wait`
listens on herdr's event stream (the socket at `HERDR_SOCKET_PATH`, which herdr sets in every pane)
and returns the moment herdr says the agent is `idle`, `blocked` or `done`, or `gone` when its pane
closes or exits. With no socket, or a stream that fails, it falls back to herdr's `agent wait` for
the rest of each slice. A builder
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
to each builder whose `wait` printed `auth`.
A turn can also stop on an API error while the session still reads busy, because background shells
the agent opened are still running. When herdr says the agent is `done` or `idle` and the last thing
in its pane is Claude Code's own error line (`⏺ API Error: ...` at the left margin, with no reply or
submitted prompt after it; the input box, which may hold a suggestion, is not read), `wait` sends it "Your last turn stopped on an API error; carry on where you
stopped." and waits again. It logs each one as a `resume` line, not a nudge, conductors included. After three such stops
in a row (a turn that ends any other way resets the count), or if the message is not taken up, `wait`
prints `stuck: api error` and exits 4. A pane that still shows the old error after a resume (the
message has not shown yet) is no new stop. An idle session still on that same pane a slice later
never took the message up. With `goal` on it never resumes a builder: it returns
`stuck: api error` at once, so the transcript still ends on the error for the goal rule. A conductor
or review agent is resumed either way. When the transcript ends on an expired login, `wait` prints
`auth` instead, busy session or not, and resumes nothing. `tell`
treats such an agent as idle and delivers, and `next` names a conductor's stop. Any `wait` also
prints `stuck: no output for <N>m (<pane>)` and exits 4 when a busy agent (its session busy, or
herdr's working for one herdr answers for) has not changed its pane for `stall_minutes` and its
transcript shows no background task still running (a shell, an async subagent or a monitor it
started, with no `<task-notification>` carrying a `<status>` for it since). A test suite running in
its pane (`make test`, `make check` or `scripts/test.sh`, as under `stall_minutes`) also keeps it
from being stuck, for a conductor as for a builder, but only until the run is 3 times
`stall_minutes` old: a hung one gives `stuck` after that. It sends nothing then: read the pane. `stuck` is
not a stall, and no close follows from it. When an agent's pane shows Claude Code's usage-limit dialog
("Stop and wait for limit to reset" / "Wait here, then continue automatically"), `wait` picks
"Wait here, then continue automatically" (the user's standing choice) once per dialog (a keypress
herdr fails to send is tried again on the next pass), logs one
`usage-limit` event for the agent in events.tsv, and keeps waiting. Only the live dialog counts: its
options among the pane's last lines with no input box under them, so a prompt quoting it sends nothing. A pane already waiting after that choice ("Usage
limit reached" with "limit resets" or "Continuing shortly") is handled the same way, with no keys
sent, while the session is busy or waiting; an idle session under that line is idle. Neither counts as a nudge or a resume, and neither turns into `stuck: no output` however long
it sits; at its timeout `wait` prints `usage-limit` and exits 1. Until the pane moves on, `status`
and `dash` show `usage-limit` for the agent in place of working or idle. `wait --stall
<slug>` also returns, with exit code 3 and `stalled: working <N> min with no commit, edit, own work in the session log or PR update`, when the
builder (busy, as above) has shown no sign of life (a worktree commit, an uncommitted edit in the
worktree, its own work in its session log, a PR update, a swarm action on its story, a test suite
running in its pane or a background task its session waits on, each up to 3 times `stall_minutes` old) for `stall_minutes` since that wait began; the line names the longest-running command the builder runs, as under `stall_minutes`.
Before it calls a builder stalled, once its PRs show no update either, it asks the signer probe
(`sign_blocked`, over the builder's worktree) whether git can sign the uncommitted work there without a
prompt. The probe says `blocked` when `commit.gpgsign` is on, the tree has changes, and gpg-agent holds no
cached passphrase for the signing key (or ssh-agent does not list the ssh key). A blocked builder is
waiting on a person to unlock the key, so the wait does not call it stalled while its last sign of life is
under 3 times `stall_minutes` old: its commits, edits, own session work, PR updates and the swarm's actions
on its story, never the start of the wait, which would keep a 60-minute wait under the cap. Past that it
may be hung on something else: the probe is not asked, and the builder stalls. A blocked builder whose pane has not changed for `stall_minutes` can still end the
wait as `stuck: no output`. The wait logs a `sign-blocked: <slug> (unsigned work since <time>)`
incident, `<time>` being the worktree's last commit in UTC, once per change of state: a later `blocked`
adds none unless a `sign-clear: <slug>` incident (the probe reading `clear` on a builder that was blocked)
or a new commit came between. When two waits on one builder probe at once, the one that takes the lock
(`.swarm/panes/<agent>.sign.lock`) logs and the other logs nothing. A probe that cannot tell (`unknown`)
changes nothing, and the builder can stall.
`wait --lead` reads these incidents for its `sign-blocked:` line (§ The lead).
So `wait` exits 0 when the agent settles (idle, waiting, gone or `auth`), 1 at the timeout or when
herdr's wait fails, 3 on a stall (`--stall` only) and 4 when stuck. `watch` is what the lead waits on: it
exits when a story PR's checks finish, when it conflicts with its base, when its head has had no checks
for 10 minutes, when it is queued (green and mergeable for `queue_minutes` with no review agent on
its head, reported once per head), or when an agent's session is waiting, and it names what the agent waits for. A
conductor's `watch --epic` or `--backlog` also returns `<repo> #<n> <branch> opened` the first time it
lists an open story PR of its own. It says this once per PR, and records it as `opened <repo>#<n>` in
`.swarm/state/watch-seen`. It says it before reading anything else about the PR, so the line costs no
gh call past the list. It never says it for a `lead` story's PR, which is the lead's, or for a
fix-main story's PR, which is in every conductor's scope. It also skips a PR whose head a review agent
has already reviewed or started on (the findings file's `head:` line, or the head on record in
`.swarm/reviews/`), so a PR reviewed before the watch first saw it is not reported as new. A rebuilt
story's new PR has a new head, so it is reported. Watches that run at once share `watch-seen`, and the
lead's rewrite of its waiting lines can drop an `opened` line written at the same moment, so a PR can
be reported opened twice; `review-agent` refuses a second start while the first is still reviewing.
The lead's bare `watch` never prints it. It polls the open PRs every minute over gh's REST API, whose hourly limit is separate from the GraphQL one that `gh pr` commands spend: the list, then a PR's mergeable state, read only for its own stories' PRs and only when a conflict or a queued line could follow from it, so never for a head it has reported conflicting, or finished and queued. A poll that reports one PR reads nothing past it. A failed read counts as `UNKNOWN` for that poll and is said on stderr. A failed list is said once, until a list succeeds again, and watch polls on. A failed check-runs read counts as unknown for that poll and is said once per PR, with gh's reason, until a read of that PR succeeds. A codex
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
The text `tell` sends starts `From the conductor:`. Run from `review-<slug>`'s pane, by the exact
record `merge` goes by (the pane's tab records name `review-<slug>` and no retired name, the newest
`agents.tsv` line for that name has role `review`, and herdr's agent in the pane holds the name), it
starts `From the review agent:`, and the goal names the review agent's findings. The sender is read
once per tell, so the header and the goal agree. The builder of a story slugged `review-<x>` is not
x's review agent, and tells as the conductor. Findings from either count the same: as a round, toward
a step-up and toward a top-rung hold.
`tell` sends only to an idle agent. After the user clears a dialog, Claude Code can still list the
agent as waiting, and herdr as blocked. For such an agent, `tell` reads the pane once. It sends the
tell only when the pane shows an empty input box with no command running and no prompt, dialog,
manual mode, login or API error over it. Otherwise it refuses as before, so its keys never answer a
permission prompt. The refusal names what the pane shows instead, or says it could not be read.
herdr refuses any prompt to an agent it reads as blocked, before sending a key, and clearing a dialog
fires no hook that would change that. So when herdr refuses a tell that way, `tell` reads the pane
again. If it is clear, `tell` reports a Claude agent idle to herdr with its session and resume
command, as the agent's Stop hook would. It says so, logs a `stale-blocked` incident, and sends the
tell once more.
An agent herdr answers for (codex, or a Claude agent with no session on record) gets no such report:
its blocked is herdr's own read of its screen. While herdr reads it blocked, the tell fails on
herdr's refusal even when the pane looks clear, and the message says no report was sent.
A tell to an agent with no pane, or whose Claude session has ended (gone), is refused once with
`could not reach <agent>: <why>; this refusal is final, so do not tell it again: <exit>`, and exits 1.
A note to a conductor whose pane is open but whose session has ended is refused the same way. The
exit depends on the agent. For a story's builder (a story on the board holds its name) it is
`swarm.sh wait --lead`'s `no-agent:` line, and for a review agent its `no-review:` line. For a
conductor it is `swarm.sh next`, which starts a new one or says why not in a `no conductor started:`
line. The agent's role in `.swarm/agents.tsv` decides which, or its name (`review-<slug>`,
`conduct-<epic>`) when it has no line there. Any other agent, such as an epic or HLD writer, a planner
or a skeptic, has no such line: the exit says to start it again with the command that started it, or
to tell the user. None of those lines
comes while herdr still lists the agent, so when its session has ended with its pane still open, the
exit starts `its pane <pane> is still open: read it (herdr agent read <agent>) and close it; after
that, ...`. The lead and the conductor list the story under no agent and never tell it again. A
`could not reach <agent> (status ...)` refusal, for a state `tell` does not know, is not final. When
herdr cannot list its agents, or lists none at all (a restart, another socket), nothing shows the
agent gone: `tell` refuses with `tell: <agent> was not
told: herdr could not list its agents; tell it again`.

**A tell to a busy agent is queued.** On 2026-10-27 a builder never got its review findings: herdr
listed it as working, `tell` refused, nothing tried again, and the builder waited over an hour. A
findings, nudge or resume tell to an agent mid-turn (Claude Code lists its session busy, or herdr
lists it working) is now queued. `tell` saves the file as `.swarm/tells/<agent>.<kind>`, prints
`queued: <agent> (busy); delivered when its turn ends, so do not tell it again`, and exits 0.
events.tsv logs that line as the tell's outcome instead of `ok`, so queued findings are not yet a
review round. An agent whose turn is over counts as idle even while background shells keep its
session busy: its session log ends on the reply that ended the turn, as for a note's wake. So a
builder at its prompt with a test running in the background is told. A newer tell of the same kind
replaces a queued one that has not been sent. So does a tell of that kind sent at once after the
agent goes idle. The newer of two tells is the one that read the agent's state later. `tell` takes
the time before it reads. A tell that goes, sent at once or claimed from the queue by its delivery,
leaves it in `.swarm/tells/<agent>.<kind>.sent`, and a queued one carries it in its file. Under the
queue's lock, a tell is the older when a tell of its kind that read the state after it has since gone,
or is now queued or on its way, whether this one then found the agent busy or idle. It prints
`replaced: <agent>'s <kind> tell, by a newer one
sent or queued meanwhile; not sent`, queues and sends nothing, and is logged with that line. The
lock covers that decision, not the send. So a tell on its way is marked until herdr has it:
`<agent>.<kind>.claimed.<token>` for a queued one its delivery claimed, `<agent>.<kind>.direct.<pid>`
for one sent at once. A newer tell of that kind that reads the agent idle meanwhile is queued behind
it, not sent at once, and a queued one's delivery waits for the next look. A mark whose process has
died counts for nothing. So a tell of a kind lands after every older tell of that kind that went and
before every newer one, the older of two that overlap is dropped, and the older never counts a round
after the newer.

Each agent with a queue has one check running in the background. It is its own process (`swarm.sh
_tell-queue-check <agent>`), so `wait --lead`'s resend pass and its `no-agent:` lines do not take it
for a tell under way. `<agent>.later` holds its last look's time, token and pid. Once a minute
(`SWARM_NOTE_WAKE_SECS`, the same minute a note's wake uses), the check reads the agent as `tell`
does. When the agent is idle, it sends the oldest queued tell through its own `swarm.sh tell`, from
the same sender, and only to the pane the tell was queued for. That tell is logged like any other,
so findings count as one round when they are delivered. If the agent is no longer idle by then, the
tell goes back in the queue. So does one whose own `swarm.sh tell` failed before it claimed the tell
(herdr down, say), up to 3 tries; the third goes to the lead. Findings that find the story's step-up
lock held (by a step-up, a restart or a hold) go back in the queue too. A step-up or a top-rung hold
that takes queued findings has delivered them: the handover or the lead's block holds them, and
`wait --lead` names a step-up that failed.

While the check sends a tell, the tell is `<agent>.<kind>.sending.<token>`, the token that
delivery's own. A newer tell of its kind can still replace it until the check's tell has read the
agent idle and claimed it. A tell replaced that way prints `replaced: <agent>'s queued <kind> tell,
by a newer one; not sent`, sends nothing, and is logged with that line. A delivery claims only its
own token, so a check that stalled past its `.later` never sends a newer tell's file. The check ends
when the queue is empty, and also when its plugin version's files are gone after an update. A check
counts as stopped once its process has ended or it has not stamped `.later` for 10 minutes; it stamps
it at each look, and once a minute while a delivery runs, so a long delivery is no stop. `wait --lead` then
hands each tell that agent has queued to the lead, as below, so none sits unseen, and the next
queued tell to that agent starts a new check. A tell a delivery had claimed when its check stopped
(`<agent>.<kind>.claimed.<token>`) goes to the lead too, as one that may have arrived. It goes first:
the lead has one line per kind, so a newer tell queued behind it is the one the lead sees.

The check drops a queued tell when the agent's pane has closed, another pane holds its name or its
Claude session has ended. It also drops one whose tell fails after claiming it, or fails before
claiming it for the third time, and `wait --lead` drops those of a stopped check. A look that gets
no agent list from herdr drops nothing, since the agent may still be there, but after 5 such looks
in a row the check hands every tell it holds to the lead. Each check counts its own looks, starting
from none: a count left by a check that ended does not shorten the next check's five. It keeps the
text of each tell it drops in
`.swarm/tells/<agent>.<kind>.undelivered.md`. A tell dropped before any `swarm.sh tell` ran for it
is logged as `tell:<kind>` with `undelivered: <why>`. A delivery that failed already has its own
tell's line, and a second line would count findings herdr sent as two rounds. `wait --lead` then
prints `tell undelivered: <slug> <kind> at <time> (<why>), exit: if it still applies, swarm.sh tell
<slug> <kind> <file>; then rm <marker> <file>` as an alert, like `no-agent:`. A later drop of the
same kind replaces the file and the line, and its own time wakes the lead again. When the why says
herdr may have sent it, the exit is `it may have arrived, so do as that says and never send it again
as <kind>`, because findings herdr sent count as a round already. With goal on, findings that
reached the builder before their `/goal` failed count as a round, and the line is `tell goal failed:
<slug> findings at <time> (<why>), exit: the findings were delivered and count as a round, and only
their goal failed, so never send them again; then rm <marker> <file>`.

**Giving up on a builder.** A conductor gives up on a builder when `wait --stall` returns stalled,
or when it is idle with no PR after wait's nudges. A PR's review rounds are its review agent's and the
escalation ladder's to limit, never the conductor's. It runs `swarm.sh close <slug> --drop`, which, on a
code, docs or chore story still `ready`, counts the attempt and clears its worktree, branch and PR,
and starts the story again in a later wave with
`swarm.sh story --strict <slug>`; swarm.sh picks the model, Fable once the story has failed `escalate_after`
builds (2 by default). With `escalate_after = 0` it reports a story that has failed twice to the lead
instead. A story that comes back `kind: lead` with `escalated_from:` is the lead's to decide, never
the user's. With `goal` on, a builder idle short of its reply is not nudged: the conductor reads the
cause from its reply and the last met `goal_status` entry's `reason` in its session log, closes it with
`swarm.sh close <slug> <cause> --drop` (`stalled` for a stall), and on `cleared-on-error` starts nothing more
in the wave and lists the story for the lead. A Fable builder can stop on its usage-credits consent, which `wait` prints as
`waiting: dialog open`. Only for an escalate build, and only once `herdr agent read` shows that
consent, the conductor accepts it with `herdr pane send-keys` in the builder's pane, runs
`swarm.sh dialog <slug> accepted` (or `dismissed`, telling the lead), which logs `dialog <slug>`
with its time, and waits on the builder again. It never closes or tells a builder over a dialog, and
a dialog is not an attempt. Any other dialog, and every permission or tool prompt, it leaves alone.
`/swarm-dev:swarm` does the same for the lead's one-off stories.

**Watching it.** `swarm.sh status` first lists, under No agent, each started story no agent works on
and each PR whose review agent never started or went,
with its exit (§ The lead). Then it lists the agents that need a look (waiting on a prompt, an empty
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
and new PR, the conductor runs `unblock --startable`, starts each story it prints as `startable:`
(§ Merging), and runs `status`, acting only on its own stories: its epic's, or for the backlog conductor those with no epic. It tells each child
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
codex loop through `swarm.sh codex-review <base>`, before it pushes re-read the comments, error text and docs that name each function, flag or error message its diff changes and fix the stale ones, reply with the PR URL when CI is green, after review fixes run only the tests for the change (`scripts/select-tests.sh --run` when its worktree has it) and leave the full suite to CI, and keep any load it starts on purpose within 4 CPUs in all, remove it when the check ends and never poll for it with a `pgrep -f` pattern that matches the poll itself), the epic's `check:` command when it has one
(the builder runs it before opening the PR), then swarm-dev's own rules from the plugin's
[`rules.md`](../rules.md), then the project's own rules from
`.claude/swarm/brief.md`, then the tagged rule lines (`<!-- lesson: <kind> -->`) of the project's
`AGENTS.md`, `CLAUDE.md` and `.claude/CLAUDE.md`, since a builder in another repo's worktree reads
that repo's files, not this project's. `herdr agent read <slug> --source recent-unwrapped` shows what an agent
is doing.

**Review before closing.** A PR that changes only board files (no code) gets one
`swarm.sh codex-review` pass plus the lead's own reading, not repeated passes. A story is reviewed when its latest head has passed
codex and, on its first round when it changes code, the `/code-review` skill. When `watch` says a
story's PR opened (`<repo> #<n> story/<slug> opened`), the conductor starts a review agent for it,
once, with `swarm.sh review-agent <slug> <PR URL>`. It starts one for every PR that opens, without
waiting for other PRs or reviews, so PRs that land together are reviewed together. It starts one the
same way on a `queued:` line, and for a story `status` lists as `kept:` once that story's builder is
open (with a `kept:` line of several PRs left to the lead). It starts one again on each
`<repo> #<n> story/<slug> checks finished on <sha>` line, so a new head gets a review at once after
the agent before it stopped; while that agent still reviews, `review-agent` refuses and nothing
starts. When `review-agent` refuses because the
worktree is not at the PR's head or has uncommitted changes, the conductor
starts it again once its `wait` on the builder returns, or on `watch`'s next line for that PR,
whichever comes first; a refusal because the agent is still reviewing needs nothing, since that
agent has the PR. A refusal that says the PR's head is GitHub's merge of the base needs nothing
either: the review agent merging the PR waits on that head. With no such head, a second refusal on
the same head with the builder idle has the builder pull the PR's head, or commit, push or set aside
its uncommitted changes (below, under a worktree behind the PR). From then on the PR is the review agent's: the
conductor never waits on the PR or the agent, reads its review file, triages, tells the builder
findings, logs a finding, closes the agent or merges. The command returns straight away, and records the head it reviews
in `.swarm/reviews/<slug>.head`. The agent, `review-<slug>`, never edits the PR's code and runs in the story's worktree and tab.
Before it reviews, it waits for the PR's checks with `swarm.sh wait-pr`, and a head counts green only
once it has also triaged `swarm.sh findings`: the notes on every check run and
the PR's open code-scanning alerts. Each real finding, a red check or a conflict goes to the builder
as `swarm.sh tell <slug> nudge`; the rest get a reason in a PR comment. After a nudge the agent waits
for the builder, then for green on the head the builder pushed. The green step runs once per round,
on the first head and then on the head the builder pushes after each findings `tell`, and each run is
bounded: at most two nudges, and at most two heads `wait-pr` calls red. Before any findings or wording nudge went to the builder, when
a green head is not the one the agent was started on, it writes `head moved: <the green head>` and stops, and the conductor starts the review
again once `watch` reports the new head's checks finished. When the builder goes idle without pushing, `wait-pr` ends the same way twice,
or the bound is reached, it writes a not-green file, which ends the green step: a round file
(`.swarm/reviews/<slug>.round.md`, below) whose
`head:` line is the head `wait-pr` waited on last and whose `## Findings` has one item,
`wait-pr: not green: <the red check, the conflict, or what wait-pr printed last>`. The
agent sends that to the builder as a findings round, as any finding, so a PR that stays red
climbs the findings ladder instead of being reviewed again and again. With `escalate_ladder` set, a
`wait-pr` that steps the build up ends the agent with `head moved: stepped up: ...`: the PR's head
has not moved, so the conductor waits on the new builder, as for its own step-ups, and the head that
builder pushes gets a new review agent when `watch` reports its checks finished. One whose step-up
failed after closing the builder ends the agent with that `step-up failed:` line as the one
finding; the line itself says to leave the story alone, as `wait --lead` tells the lead, whose exit
is `step-up --resume`. Before it reads the diff, each round, it runs `swarm.sh dropped-lines
<owner/repo> <n> <head> <base>` in the background on the round's head: the head its brief names on
round 1, and from round 2 the command `review-agent --next` prints, on the head that round pins. A
run that is killed, or that exits with anything but 0 or 1, counts as exit 2. On exit 1, each line
it printed is a base line one of the PR's own merges dropped. The check reads each merge and never
the head, so it prints a line again after the builder has put it back. The agent counts the
whole-line copies of the text in the merge's file and in the round's head, with control characters
such as tabs taken off as the check takes them off
(`git show <rev>:<file> | LC_ALL=C sed 's/[[:cntrl:]]//g' | grep -cxF -- '<text>'`). A line
is fixed only when the head's count is at least the merge's plus the times the check printed it, so
another copy of the text, or a longer line holding it, does not count. A line the check cut to 300
characters never matches and stays a finding. Each line
not back is a finding to fix this round, whatever else the round finds, and the builder is told to
restore it in a commit of its own. Once a later round finds it back, it is logged
`log-finding --reviewer conductor --round <n> dropped-lines <PR URL> "<first line>"`. When the
builder answers in the PR that the drop is meant, the agent may accept that as a decline. Its reply
on the pass then names the drop and the answer, so whoever merges sees it. An exit 2 (it could not
check) is run once more, since a GitHub or fetch error can clear. On a second, the agent nudges the
builder with the line and stops with no pass: its review file holds `head:`,
`dropped-lines unchecked: <the line>` and a `stopped:` line, and the stop note goes to the conductor. It
runs `codex-review` with `SWARM_STORY=<slug>` and `SWARM_PR=<PR URL>`, so codex also sees the
findings declined on this PR in earlier rounds, and, on the story's first round when the PR changes
code, `/code-review <PR URL>`. From round 2 on it runs codex alone. It runs no tests of its own
and trusts CI, unless `review_verify = full`: then round 1 may also run the project's tests for the
changed files and check the builder's mutation proofs, and later rounds still trust CI (reference-models.md
§ Settings). `review-agent` counts the round
from the findings rounds since the story's last build started: each findings `tell` that went out,
or that herdr sent without seeing it taken up, and each findings step-up, whose brief carries the
findings in place of a tell. A `review-agent --recheck` refused with a full round due counts too, at
most once per round. A step-up or a restarted builder does not start the count again. Nor does a
build started after a kept close (its `kept` event, then that close's own line; reference-models.md
§ Model and effort), unless the slug has a later ok close, reset or drop, or reconcile reopened it
because the kept PR closed unmerged: until then the kept PR is still the one under review.
After each review the agent triages its own findings. It never edits the code: a finding that is
real and inside the story goes to the builder to fix. From round 3 the round cap narrows that: the
round's line, in the brief or from `review-agent --next`, has the agent send only a regression the PR
introduces or a line now false about the code, and decline the rest as `deferred`. A deferral
carries no `--because`, since the builder gave no reason and the call is the agent's. Each declined
finding gets a reason (nit, wrong, out-of-scope, deferred, or the reason an earlier round gave), and
the agent rebuts them all in one PR comment. It logs each declined finding at once, with
`log-finding --declined <reason> --reviewer <who> --round <n>`; a finding a fallback reviewer raised
in codex's place is logged with `--reviewer fallback`. It logs the ones to fix once the
builder has pushed and `wait-pr --head` has found the PR at that head, never from the worktree's
commit alone: from the builder's reply and the new diff, each one fixed as fixed, and each one
the builder declined with a reason the agent accepts as declined, with the builder's reason in
`--because "<one line>"`, rebutted in the PR; one declined
with a reason it rejects is not logged and comes up again next round. Then it writes the review. A round with nothing
to fix is a pass, and the agent writes its review file, `.swarm/reviews/<slug>.md`, first: a
`wait review-<slug>` (the lead's, for a kept story) ends on that file, and once the PR merges, the merge's reconcile retires the agent and
removes its worktree. Then it hands the PR on itself. It runs `swarm.sh review <slug> --head <SHA> <PR URL>` with the head it reviewed, which
puts the story in review. Then, under `merge = agent` or when `swarm.sh grants <PR URL>` lists
`merge`, it runs `swarm.sh merge --head <SHA> <PR URL>` on that head. Otherwise the review is the
handoff, and the PR waits on your merge. A `grants` that fails is run once more, and a second failure
hands the PR over too. `review --head` and `merge --head` both refuse a head pushed since the review:
the agent then writes `head moved:`, sends its conductor a stop note naming that line (below), and
stops. The conductor starts a new review agent on the new head on that note (the lead does when no
conductor runs). When it was `merge` that refused, the story
is already in review on a head nobody reviewed, and the agent's reply says so first. `review --head`
also refuses while the story has a PR the agent did not review, on its `prs:` line or open from its
branch `story/<slug>`, so a story with two PRs never finishes with one of them still open. When the base gained code since the head's CI ran,
`merge` merges the base in, waits for the new head's CI and merges that head itself (§ Merging,
Waiting for the new head), so after `base merged:` the agent leaves it running until it exits. A
`base merged, <cause>:` refusal goes back to the conductor or the lead as any other refusal does. A
`held:` refusal leaves the PR for you. A stacked story that `review` holds until its parents merge
(`held: <slug> waits for <p> to merge`, printed after `swarm: `) sends that line as its stop note. The conductor then nudges
no builder and starts no review agent. Once <p> merges, its Stacked rule has the builder merge it
in, and the new head gets a review agent.
It replies with the file and what the last command printed. A round whose findings the builder
declined, each with a reason the agent accepts, and pushed nothing for, passes the same way. Every
`swarm.sh` call in its brief names the project (`SWARM_PROJECT`), as the agent runs in the story's
worktree. With findings to fix, it writes the
review to `.swarm/reviews/<slug>.round.md` instead: the review file is read as a finished review of
the head on its `head:` line the moment it exists, by `swarm.sh wait review-<slug>` and by the
`queued:` check of which heads have a review, so the agent writes it only on a pass or when it stops. It then runs
`swarm.sh wait --stall <slug>` and `swarm.sh tell <slug> findings <the round file>`, so the findings
go at once and count their round now; a tell that finds the builder busy is queued and sent when its
turn ends (above), and the agent then waits out that turn, then the delivery, with one bounded
command in the background (its marks under `.swarm/tells/` gone but `.sent`, 15 minutes at most,
since a check that has not looked for 10 minutes counts as stopped; an `.undelivered.md` there, or
the limit, stops the agent). A delivery
that held the story for the lead or stepped the build up leaves `.sent` too, so before it waits for
the fix the agent reads the story's `held_for:` line, which stops it, and the events log's
`escalate` line for a findings step-up, after which it tells the new builder nothing and waits on
it. Every wait on the builder is `wait --stall`, and the agent
carries on when it prints `idle`, or `done` for a builder with no Claude session. With
`escalate_ladder` set, a stall it steps up (`stepped up:`), or a step-up or restart already running
(`stepping up:`), is waited on again, and a build stepped up after the round's findings were told
gets the round file as a nudge, since its handover brief pastes only the review file; a wait that
ends any other way (stalled, stuck, timed out) stops the agent. When `tell` says the build was
stepped up, the agent waits on the new builder, which has the findings in its handover brief. A
`tell` that fails but says the findings count as delivered, or as a round, was sent: the agent
reads the builder's pane when `tell` says to, resends the findings as a nudge only when they never
arrived, and carries on. When `tell` says the story is held for the lead, or its step-up failed
partway, the agent stops. Once the
builder has pushed, the agent runs the green step on the new head with `wait-pr --head <that head>`,
since right after a push GitHub can still report the old one; when that wait says the PR's head is
another, the push never landed, and the agent nudges the builder naming both heads and runs
`wait-pr --head` on the same HEAD again before it calls the builder idle without a commit, then
`swarm.sh review-agent --next
<slug> <PR URL>`, and reviews the round that prints in the same session. When every finding to fix
is wording (a comment, doc or error-text line that misstates the code), each citing the one
`file:line` it rewrites, the agent sends the round file as a nudge instead of a findings `tell`. A
nudge is no round, so the ladder does not move. Once the builder's push is green, the agent runs
`swarm.sh review-agent --recheck <slug> <PR URL> <the head it reviewed> <each file:line>`, each path
relative to the repo root, in place
of `--next`. A pass writes the review file, and the agent hands the PR on as for any pass, with the
rechecked head. A refusal that names `--next` counts
the round, and the agent runs `--next` and a full round. If the builder goes idle
without pushing, the round passes when the builder declined each finding with a reason the agent
accepts, rebutted in the PR as its own declines are; the agent stops otherwise, as it does when the
wait fails. A stop before a pass writes the review file
with two lines, `head: <the PR's head>` and `stopped: <why>`: with no `## Findings` heading it is no
pass. The agent then tells its conductor with a note, `review-<slug> stopped on <sha>: <why>`
(`swarm.sh tell <conductor> note`), since the conductor reads no review file. The conductor acts on
the why as on its own wait on the builder: a stall or a stuck builder by its give-up and stuck rules,
and a builder that pushed nothing with one nudge, then a new review agent once the builder is idle.
A second stop of the story for the same reason goes to the lead. With no conductor running, the
tell fails, and the agent's reply says the lead takes the story; `wait --lead`'s `stopped:` line
(§ The lead) brings it to the lead. The next head the builder pushes
gets a new review agent when `watch` reports its checks finished.
How each kind of stop reaches an owner:

- A moved head. A builder can push while the old review agent is still in its session (mid-round,
  or after a pass while `swarm.sh merge` runs). `watch` prints `checks finished` for that head once,
  and `review-agent` refuses the conductor's start then. So every stop on a moved head (`head moved:`,
  in the green step, after the review, or from `review` or `merge`) also sends the conductor the stop
  note, its why that `head moved:` line, and the conductor starts the review agent again on it. A
  `head moved: stepped up:` stop sends none: the head is the same, and the new builder's push gets
  its review from `watch`. When
  `review-agent` refuses because `review-<slug>` is still working (it is ending the turn that sent the
  note), the conductor starts it again once `swarm.sh wait review-<slug>` returns, the one wait on a
  review agent it runs.
- A worktree behind the PR. `review-agent` refuses while the story's worktree is not at the PR's
  head. When events.tsv has `merge <slug> base-merged <that head>`, the head is GitHub's merge of the
  base into the PR, and the refusal says so: the merge that made it waits on it, so the conductor
  starts nothing. With no such line, a second refusal on the same head with the builder idle gets
  one nudge, by what the refusal says. A worktree at another commit is behind the PR, so the builder
  pulls the PR's head (`git pull --ff-only origin story/<slug>`). A worktree with uncommitted changes
  is not fixed by a pull, so the builder commits and pushes them, or discards each by copying its file
  aside. The conductor starts the review agent again once the builder is idle.
- A passed head. `review-agent` refuses a head its findings file already passes (as `review_pass`
  reads it) once the story has left `ready`, so a `checks finished` line after a pass never starts a
  second review that could send findings to a PR its merge is landing. A story still `ready` never
  got its hand-off (`review --head` failed), so a new review is how it goes on. The lead moves the
  file aside first to review a handed-off head again.
- A held stacked story. Its stop note waits for the parent's merge, as above.
- A fix-main story. It has no epic, but an epic's conductor builds it. The review agent's stop note
  goes to the conductor that started its build (the pane on its `story` line in events.tsv, named in
  a tab record as a conductor), as a merge note does, not to the backlog's.
- No conductor. When the note's tell reached no conductor that still runs (no pane, its report
  written, or started again since), `wait --lead` prints `stopped: <slug> (<the note>), exit: ...`
  until a review agent starts on the story again or it leaves the board. A story in review that
  waits on the user's merge gets none, and a note younger than 120 seconds waits for its tell.
It judges the PR against the story's touches and **Done when**. A point that only a change to a file
outside the touches can fix is out of scope; a gap in the PR's own code is a finding, even where the
touches do not name it. There are two exceptions, and both are findings even when the file to fix
is outside the touches. A comment, doc or error-text line that the changed code no longer matches
is reported at its `file:line`. A PR that changes what a user runs, sees or must do, and does not
update README.md, AGENTS.md, docs/ or the command text to match, is reported at the stale doc's
`file:line`, or at the change when no doc covers it yet. The brief's example is swarm-dev's own
`env:` line, which kept describing the old env allowlist after the code changed. Its brief
carries the checks the lead used to make by hand, and so does the fallback reviewer's brief. Both
also carry the rules a builder gets, in the same order: swarm-dev's [`rules.md`](../rules.md) first,
then the project's own. After the checks come the
lines of the story and its epic that hold a `(user, <date>)` mark. Each is printed as it stands, with
its `path:line`, cut at 1500 bytes on a character boundary, and the brief tells the reviewer to read
each decision in full at that line. Together they take at most 2000 bytes; past that, the brief says
how many were left out and which files hold them. A mark inside code or a fenced block, or in the
story's own **Done when** (which the brief already quotes), is not a decision. A PR that contradicts
a decision is a finding, even when the PR is stricter. The fallback reviewer gets the decisions
only when codex-review knows the story (`SWARM_STORY`). It writes to the absolute
path `<project>/.swarm/reviews/<slug>.md` (its working directory is the worktree, outside the
project), and replies with that path. It writes the file in one go once both reviews are done,
after `review-agent` has removed the one from an earlier head. The file starts with `head: <SHA>`,
the PR's head, which `review-agent` reads from `gh` and puts in the brief, then `codex skipped:
<why>` when codex was skipped. Under them go the findings to fix,
each with its reviewer and file:line, then, under one `## Handled by the review agent` heading, the
findings it declined with their reasons and the points raised outside the story, marked out of
scope. It uses no `## Declined` or `## Out of scope` heading, since it has logged and rebutted
those already.
With findings to fix, the same review
goes to `.swarm/reviews/<slug>.round.md`, the round file the agent tells the builder, and the
review file is written only on a pass or a stop (above).
`review-agent` refuses, starting nothing and leaving the last review's file in place, when the board has a story named
`review-<slug>` (whose builder would hold the same agent name), when the worktree is not at the PR's
head or has uncommitted changes, when its findings file is a pass of the PR's head and the story is
no longer `ready`, or when
`review-<slug>` is still working or still open with no findings file (idle while its codex runs, not
finished). It moves the last review's file aside
before the new agent's brief goes, puts it back if herdr cannot start the agent, and deletes it once
the agent has started. When the start fails, `review-agent` first reads the error. If herdr may
have sent the brief (its reply could not be read, or the brief was sent and not taken up) and
`review-<slug>`'s session reads busy or waiting (herdr's working or blocked for codex), or reads idle
with the brief in its log (a review agent sits idle while its codex runs) and its login has not
expired since, it says the
agent is running, records the head, keeps the file aside as `<slug>.md.prev` and exits 0; `wait
review-<slug>` then waits for a new file. If herdr may have sent the brief to an agent that is not
running, it keeps the file aside, records no head and fails, saying how to close the pane and start the
review again; so does a start whose agent herdr cannot list, since its state is unknown. In every
other case (herdr surely sent nothing, no pane, a session that is gone, or one herdr has no status
for), it closes the pane, puts back the file it moved unless a new findings file is already there,
and fails. A `.prev` an earlier start left, with no findings file since, stays where it is. For a story stacked on
parents, the brief names their branches: their code is in the diff against the base, but the agent
lists it neither as a finding nor as out of scope. A wait on a review agent, `swarm.sh wait
review-<slug>` in the background, is the lead's, for a kept story; the conductor runs one only to
start a review again after a stop note on a moved head, once the agent that sent it ends its turn. A review
agent goes idle while its codex runs in the background, so for an agent agents.tsv records as role
`review`, that wait, like a wait on a conductor, holds on until the findings file exists, and fails if
it times out without one. That wait's limit is an hour by default (`swarm.sh wait review-<slug> [ms]`);
a review agent that spans rounds (a builder's fix, CI, a codex run each) can outlive it. The review
agent sends its own findings to the builder with `swarm.sh tell <slug> findings`, and logs them. A
round is one review whose findings went to the builder; a review started again (head moved, no
findings section, a review agent that timed out or crashed) is not one. A review on the latest head
whose findings are all declined is a pass, never sent to the builder. Each declined finding is
rebutted in the PR with a reason and logged with `log-finding --declined <reason> --reviewer <who>`:
`nit` for a nit, an edge case or a low-value point, `out-of-scope` or `wrong` where they apply,
`deferred` for one the round cap holds back from round 3, and a point already declined with the
reason it was first declined with. Before a story goes to review or
merges, `review --head` and `merge --head` check that the PR's head is still the one the agent
reviewed. A PR whose head has been green and mergeable for `queue_minutes` with no
review agent on that head is `queued`: `watch` returns `queued: <repo> #<n> <branch> green <m>m with no review on <sha>`,
and `next` prints the same line, naming the conductor, for the lead to send it (§ Settings, `queue_minutes`). `tell`'s kind (`findings`, `nudge`
or `resume`) is required and goes in the audit log. `tell` sends only to an idle session. A tell
to a builder that is still working is queued and sent when its turn ends (§ A tell to a busy
agent is queued). `tell` refuses a builder waiting on a prompt (it names what the prompt is), or
whose session is gone or unknown. A builder listed as waiting whose pane shows an empty input box
is told (§ Building, under **The goal.**). herdr can read a pane idle through a whole turn, so a message or brief
(a `tell`, or a start's brief) counts as taken when the agent's own Claude session shows it, too: the
session reads busy or waiting (when it read idle before the send), or its log
has the message as a new prompt (for a `tell`, the file's first line). herdr's own status, even
`unclear`, does not outweigh that. When the session read idle before the send and shows no sign of it,
the message goes once more, and the command fails if it still shows nothing. A message herdr sent to
an agent whose session was not idle before the send (not listed yet, busy, or unreadable) counts as
taken only when its log has it, and is never sent again; neither is one to an agent with no session
to read (codex). When nothing shows a turn, the command succeeds and warns that herdr sent it the
brief and did not show the turn start, but only if herdr read the agent before the send and reads
it, with no turn finished since, idle both times or done. With no read from before the send, it
fails, saying the agent may or may not have it. To reach a busy conductor, the lead runs
`swarm.sh tell conduct-<epic> note <file>`. It appends the file under a timestamped header to
`.swarm/inbox/conduct-<epic>.md`, and only for a live conductor of this project. A conductor
whose turn has ended (idle, or busy only with background jobs, as `upgrade` reads it) also gets a
short prompt telling it to process its inbox now, by the steps below, run `swarm.sh unblock
--startable <epic>` (or `--backlog`) and start what it prints, then end its turn, leaving any wait or
watch it has running alone (it starts one only if none runs). A wait can run a long time before it
returns. `tell` sends the prompt once and returns without waiting for it to be taken up. One
conductor gets at most one such prompt a minute: `.swarm/inbox/conduct-<epic>.woke` holds the last
one's time, set under `conduct-<epic>.lock` so of two notes at once one sends it (a lock left over a
minute is cleared; one held past 5 s is warned of). A note also leaves one check pending in the
background (`conduct-<epic>.later`): once the minute since the last prompt is up, it prompts the
conductor that holds the name then, if the inbox is still there and no prompt went out meanwhile. A
prompt sent while the check waits moves the check once, to the end of that prompt's minute. So a
burst of notes sends one prompt now and one a minute later, and a prompt that was dropped, or
answered without reading the inbox, is sent once more. A prompt that fails is warned of and its time
taken back, so the next note tries again. No prompt goes to a conductor mid-turn, one that has
written its report, or one that `upgrade` asked for a handover and has not yet told to carry on
(`conduct-<epic>.upgrade`, which upgrade touches each round and which is ignored once an hour old). After each `wait` or `watch` returns, the
conductor moves the inbox with `mv` to `conduct-<epic>.reading.md` beside it (so a note added
meanwhile starts a new file), reads that copy, acts on it and deletes it. A copy already there is a read that was cut off,
so the conductor reads and deletes it first. It does all of this once more just before it writes its
report, so a note left after its last wait is still read. Once a new conductor has started,
`conduct` clears both files, and the `.woke`, `.later` and `.upgrade` beside them, so it never acts on notes left for the one before. A `conduct` refused
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
and holds out of scope only a point that a change to a file outside the touches alone can fix. With
`SWARM_PR=<PR URL>` too, as the review agent runs it, the prompt ends with the findings declined on
that PR before: each `.swarm/findings.tsv` declined row whose PR is the same PR (a URL or `owner/repo#N`,
never one whose number only starts the same), with its round, its reason and its `--because`. A line
over them says each reason is the builder's claim, not a fact, and that codex ignores none of them.
With no such row, or with no `SWARM_PR` (a builder's own run before its PR opens), the prompt is
unchanged. On a usage limit the fallback reviewer's brief carries the same prompt. If `SWARM_STORY` is not a slug, names no story file,
or names a story with no **Done when** item, or `SWARM_PR` is set and is not a PR URL, codex-review fails before codex starts. An interrupted
codex-review stops codex the same way and exits only once it is gone. While it runs it keeps a marker,
`.swarm/state/codex-review.<pid>` (start time, base, worktree), which the dash reads for its codex
row. It removes its marker when it exits, and on start removes any marker whose process has died. codex stays in the caller's
process group, so a harness that kills that group kills codex too. On macOS a KILL to the group can
miss a child that codex forks while the KILL is sent, so a harness that must leave nothing STOPs the
group first. Every brief says to run it in the
background (Bash `run_in_background`) and wait for it: Claude Code stops a foreground Bash call at 2
minutes by default and 10 at most, before the limit could apply. Whoever runs it waits for it to
exit and acts on what it prints last, since a usage limit printed early may be followed by a
fallback's review. When it ends on codex's usage limit or on `codex skipped: ...`, no one runs it again: a
builder carries on, a story's review agent or the lead reviews the diff itself, and the PR says `codex
skipped: usage limit` or `codex skipped: timed out`. A review agent says `codex skipped: <why>` in
its reply and on its review file's second line, and in a round with no `/code-review` it reads the
diff itself in codex's place. codex-review sends codex's
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

A codex review reads the diff. In this repository, swarm-dev's own, its `scripts/test.sh` refuses to
run under codex, and so does its `make test`: when `CODEX_SANDBOX` or `CODEX_THREAD_ID` is set,
`scripts/test.sh` prints one line and exits 1 before it runs a file or writes `.swarm/test-runs.tsv`,
and `make test` then exits 2 with make's own error line after it. `init` copies no test runner, so a
project of your own gets no such refusal. codex 0.164 sets both variables in the shell it runs
commands in. The lead's shell and an agent's pane have neither, so the refusal stops no builder.

## Commands

| Command | What it does |
|---|---|
| `swarm.sh status` | Show started stories with no live agent and PRs whose review agent never started or went (No agent, with each one's exit), agents that need a look (each row ends `[pane <pane>, workspace <label>, tab <label>]`, as `where` prints them, with herdr's workspace and tab lists read once, after pane_check's pane reads and before status_report.py's, with the Stacked, Waiting on you and Next reads after them; a tab with no label shows the name swarm-dev gave it), stacked builds whose parent moved or merged, what waits on you, and what runs next. Its herdr, gh and claude reads, each agent's pane read included, and its git fetch and ls-remote, share a 30-second deadline (`SWARM_REPORT_SECONDS` sets another, for a test). One network read is left out on purpose: `git remote set-head origin --auto`, which a stacked build's check runs when `base_branches` is empty. It writes `refs/remotes/origin/HEAD`, and cutting it mid-write would leave a stale ref lock. A `git fetch` cut at the deadline can leave the same kind of lock: a `.lock` file under the repo's `.git/refs/` that fails later fetches of that ref, builds' and merges' included. Deleting the file clears it. A read cut off there, or due after it, counts as a failed read, so its section shows what it shows when that read fails, and a last line such as `skipped (over 30 s): herdr agent list, gh pr list` names it. |
| `swarm.sh next` | Print the next step on the first line, and why on the lines after it. While a conductor works, it also starts a conductor for any ready work that has none (§ Building). Its reads of herdr, gh and Claude Code's session list share 30 s, counted from when it starts reading (`SWARM_REPORT_SECONDS`), the reads that decide a conductor start included. It reads herdr's agent list once and answers every later agent list from it. A read still running at that point is cut, the step is worked out without it, and a `skipped (over 30 s): <reads>` line after the step names each cut read, such as `herdr agent list`, `gh pr list` or `ci_gate age`. A cut read can change the step. Without herdr's agent list it can miss a working conductor. Without `claude agents` or `herdr agent read` it can show a conductor stopped on an expired login or an API error as still working. Once a read that decides a start is cut, next starts no conductor, and names each one it would have started: `no conductor started: <conductor>: a read it needs was cut at the report's deadline; run swarm.sh next again`. So run `next` again whenever it prints a skipped line. Writes, and a start once begun, are never cut, so a slow start runs to its end. |
| `swarm.sh dash --watch` | Open the live dashboard: a running-now box, how long each working agent has gone without a sign of life, how long each running codex review has run, and a merges-per-day speedometer with two warning lights, and a third when someone had to step in. `swarm.sh dash --project <dir>` (repeatable) draws several projects. Each frame's herdr, Claude Code and gh reads, each agent's pane read included, share 30 seconds (`SWARM_REPORT_SECONDS`), the gh reads at most half of them; a read still running then is stopped, a later one is skipped, and the frame is drawn from the rest with a last line naming them: `skipped (over 30 s): gh PR states, herdr agent list`. A PR a cut gh read did not reach keeps the state from whichever run last read it, until one reaches it again. With `--project` each project's frame has 30 seconds of its own. `swarm.sh dash --check` compares each figure with the command that owns it and exits 1 naming each one that differs. Its frame, and the `status` and `next` it compares with, read everything in full. With `lead = session` in the config, only your own steps say needs you; the rest goes in a lead's queue ([details](dash.md)). |
| `swarm.sh conduct <epic>` | Start a fresh conductor for one epic. `swarm.sh conduct --backlog` starts one for the ready stories that have no epic. `watch --backlog` follows their PRs. Under `merge = agent` it refuses while Claude Code's settings have no allow rule for `swarm.sh merge` (§ Merging, the conduct preflight). |
| `swarm.sh wait --until-report conduct-<epic>` | Wait, with no timeout, until an epic's conductor writes its report, waits on a prompt, exits or needs a login. `/swarm-dev:swarm` runs it for you. |
| `swarm.sh review-agent <slug> <PR URL>` | Start a review agent for one story's PR, scoped to its `touches` and **Done when**. It writes `.swarm/reviews/<slug>.md` and returns at once; a conductor runs it once for each PR that opens. When a start runs nothing, it waits 3 seconds and starts again, up to 3 starts in all, so it can take three times as long. That covers herdr's `pane ... not found`, `the pane's shell did not take the agent's environment` and `agent_not_found` with nothing sent, and an unclear start that left no agent running (no pane, a session that is gone, or no status from herdr). Each try logs `review-agent:try <slug> (try N of 3) started` in events.tsv as it begins, before the brief goes out. Each failure it retries logs a `review-agent <slug>` line ending `(try N of 3)`, and a third failure is the command's own line, ending `(try 3 of 3)`. An unclear start whose agent runs or cannot be listed is never tried again. When the command is cut off with tries left, `wait --lead` runs it again from the next try ([§ The lead](reference-lead.md#the-lead)). The agent never edits the PR's code. On a pass it runs `swarm.sh review <slug> --head <SHA> <PR URL>` with the head it reviewed, then merges the PR with `swarm.sh merge --head` under `merge = agent` or a `merge` grant, or leaves it for you ([§ Building](reference-building.md#building)). |
| `swarm.sh review-agent --next <slug> <PR URL>` | Run by `review-<slug>` from its own pane: its next review round, in the same session, with no new agent. Once the worktree is at the PR's head with nothing uncommitted, it moves the last findings to `.swarm/reviews/<slug>.md.prev`, records the head, and prints the round and what it runs (codex alone from round 2, and no tests of its own, whatever `review_verify` says), then the `swarm.sh dropped-lines` command on the head it records, against the story's base (`base_for`). It refuses, changing nothing, in these cases: when it cannot tell that base; from any other pane; when the board has a story named `review-<slug>`; when no findings went to the builder since its build started, by a findings `tell`, a findings step-up or a `--recheck` refused with a full round due (round 1 is always a plain `review-agent` start); when this build has no ok `review-agent` start, so the pane is an earlier build's; and while that round has already started with no findings sent, and no such refused `--recheck`, since, so it never puts a finished review aside unread. When herdr cannot list its agents, it says to run `--next` again, not to start a new review agent. events.tsv logs it as `review-agent:next <slug> ok (round <n>)`, which flow's review-agent start counts and review_wait do not read; `outcomes`' `green_to_review_min` reads it as a round start. |
| `swarm.sh review-agent --recheck <slug> <PR URL> <old head> <file:line>...` | Run by `review-<slug>` from its own pane after the builder pushes a wording fix, in place of a full review round. `<old head>` is the head it last reviewed, as `.swarm/reviews/<slug>.head` records it, and that round's findings to fix must already be written to its round file, `.swarm/reviews/<slug>.round.md`. Each `file:line` must appear in that file's `## Findings` section as a whole path (or under the worktree's own path), with the line number as at `<old head>`, every finding there must cite one of them, and every `file:line` a finding cites must be one of them (a range or list such as `doc.md:3-5` or `doc.md:3,8`, or a bare `:8` later in the finding, never is). It passes only when the worktree is at the PR's new head with nothing uncommitted, `git diff <old head>..<new head>` rewrites each named line and nothing else, and the new head is green. Every line the diff removes or rewrites must be named, and no hunk may add more lines than it removes. A file added, deleted, renamed, binary or with a new mode fails it, and so does an empty diff. On a pass it writes the new head's findings file, `.swarm/reviews/<slug>.md`, as a pass (its `head:` line, a `## Findings` section saying the wording recheck passed, and a `## Handled by the review agent` section carrying the round file's, the points the agent declined or found out of scope and already logged and rebutted), keeps any file already there as `<slug>.md.prev`, and records the new head. events.tsv logs it as `review-agent:recheck <slug> ok`, which counts no round, so the next `--next` prints the same round. Otherwise it exits non-zero, writes nothing under `.swarm/reviews` and says why. When the old head, its findings or the diff rule the recheck out, or the new head is red, it names `swarm.sh review-agent --next <slug> <PR URL>`, the full round that is now due. That refusal counts the round the wording nudge did not, once per round, so the `--next` after it runs. When CI on the new head is still running it says to wait (`swarm.sh wait-pr`) and run `--recheck` again, and when it cannot read CI within 60 seconds (`SWARM_RECHECK_CI_SECONDS`) it says to run `--recheck` again. A bad argument, another pane, a board story named `review-<slug>`, herdr not answering, or a worktree not yet at the PR's head says what to fix first. |
| `swarm.sh story [--strict] <slug>` | Build one story. It warns when an open story of another epic touches the same part (by its first word) or both name the bare file; `--strict` refuses instead, and conductors always pass it ([details](method.md)). It refuses a story whose file in the main checkout has an edit `origin/<base>` lacks, uncommitted or in a local commit ([§ Building](reference-building.md#building), Board state). When a start runs nothing, it waits 3 seconds and starts the builder again in the same worktree with the same brief, up to 3 starts in all. That covers herdr's `pane ... not found`, `the pane's shell did not take the agent's environment` and `agent_not_found` with nothing sent. Each failure it retries logs a `story <slug>` line in events.tsv ending `(try N of 3)`, and a third failure is the command's own line, ending `(try 3 of 3)`. A start whose brief may have gone (herdr may have sent it) is never tried again, and neither is one whose pane may still be open: it could not be closed, or herdr could not list its agents or panes. Running `swarm.sh story` again on a story that has started is refused: it has a build already. |
| `swarm.sh plan-unasked [--declined] <epic>` | Record, in board state, that a `later` epic `next` offered (its dependencies done) has had its unasked plan. The lead runs it before that `/plan-epic`. `next` offers the epic no more. The gate lists it as planned unasked on that date: with no stories yet, run `/plan-epic <epic>` again if that plan stopped; with stories, set it `active` with `agreed: <today>` to start it. With `--declined`, the user declined the plan, and the gate says that instead. |

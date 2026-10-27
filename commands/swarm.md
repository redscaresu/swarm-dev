---
description: Use when asked to build, continue or run the epic, the swarm or the next step. Runs the whole chain from wherever it stands (epics, stories, builds), stopping only where the user must decide
---

The board is the directory `swarm.sh config board_dir` prints (`docs/` unless the project's
`.claude/swarm/config` says otherwise); every `docs/epics/` and `docs/stories/` below
is inside it.

Drive the chain end to end, picking up wherever the board says it stands. Requires herdr
(`HERDR_ENV=1`); if not inside herdr, say so and stop. Read `${CLAUDE_PLUGIN_ROOT}/docs/method.md`
and, for the sections it names, `${CLAUDE_PLUGIN_ROOT}/docs/reference.md` first if you have not this session.

If `<board>/stories/README.md` does not exist, the project has no board yet. Offer to run
`swarm.sh init` from the project's git root, and wait for the user's yes before you run it. It adds
the board, `.claude/swarm/`, the `.gitignore` lines, a CI workflow and a pre-commit hook, then tells the user to run `claude` there once
and accept the folder trust prompt. Only the user can do that, so stop after it.

If `.claude/swarm/brief.md` does not exist, ask the user once, in one message, for their commit
trailers, where credentials live, and commands that must never run. Write only what they said to
`.claude/swarm/brief.md`, under 4 KB. If they decline, write an empty file so they
are not asked again. Do not commit it. Tell the user to commit it, even empty: an untracked brief
stops `swarm.sh reconcile` from pulling a PR that adds the file.

When the board is in the project's repo, make each board edit you write by hand (a re-scope, a new
story, an unblock) in its own worktree with `swarm.sh board-pr`, never in the main checkout. A board
outside the repo is edited where it is, since `board-pr` refuses it. A conductor's scope or body
edit to a story goes through `swarm.sh board-pr` too (its brief says so). `swarm.sh finish` and
`swarm.sh drop` open their own board PR, `finish-<slug>` or `drop-<slug>`, and print the
`swarm.sh merge --board <url>` that lands it: run that, or with `merge = human` hand the PR to the
user, unless `swarm.sh grants <url>` lists `merge` for it, which lets you run it. A `costs: money`
PR, or one stacked on one, stays the user's to merge, grant or not. Once it has merged, `swarm.sh board-pr done <that name>` clears its worktree away.

`swarm.sh board-pr start <name>` prints the worktree's path, `<repo>-wt/_board-<name>` (beside the
story worktrees, never one of them), on a new `board/<name>` branch from origin's base. Edit the
board there, then run `swarm.sh board-pr open <name> "<title>" <body-file>`. It refuses if anything
outside the board changed, and otherwise commits with the brief's trailers, pushes and prints the
PR's URL. Run it again to push more edits to the same PR. Once the PR has merged or closed, `open`
refuses, and `swarm.sh board-pr done <name>` removes the worktree and the branch, here and on origin;
run `start` again for the next edit. `done` also clears a start you abandoned with nothing committed.

First run `swarm.sh version`. If it prints a WARNING, show it to the user word for word, then carry on:
an old version still runs.

When the user has updated the plugin while a conductor runs, run `swarm.sh upgrade` (with no
epic, it moves every agent the project started). It moves them to the new version with `--resume`,
so each keeps its context. It runs detached, prints its pid and its log
(`.swarm/upgrade-<version>.log`), and works in rounds until every agent is moved or 2 hours pass.
Only one runs per project: a second prints the running one and starts nothing. While it runs,
`swarm.sh status` names it and the agents still on an old version. Once status no longer names it,
read the end of its log, one line per agent, and show the user each agent left on its old version
with its reason.
While it runs, upgrade stops each conductor, so your background `swarm.sh wait --until-report` on a
conductor may return. Ignore that return until upgrade is done: do not restart or nudge the
conductor, and do not start a second `conduct`. Then wait on the conductor again.

Repeat until a step below says stop:

1. Run `swarm.sh reconcile` (it takes off the board what you merged, and puts back to `ready`
   what was closed unmerged; an item whose PR left its file on a board in the repo is marked done
   instead, so run the `swarm.sh finish <slug>` it prints), then `swarm.sh unblock` (it readies stories whose blockers have
   merged), then `swarm.sh next`.
   Its first line is the step, the rest is why. Tell the user both in one line. Lines that
   start `idle:` come after the step and name capacity no step uses; do the step, and handle each
   one too:
   - `idle: <story> waits on <dep> but shares no touches part with it and needs nothing from it`: the
     dependency looks over-broad. Both are stories an agent builds, and the dependency is not in review
     (a story a review holds is left out too). No entry of the story's `touches` clashes with one of
     the dependency's (the same file and the same first word of the part, or both the bare file), and
     the story's `needs:` line does not name the dependency. Drop it from the story's `depends_on`, so
     the story builds beside its dependency; or keep it and name it in the story's `needs:` line with
     what the story uses from it (`needs: <dep> (the function, the flag, the file)`), which silences
     the line. When you drop it and no other
     `depends_on` of the story is still open, set the story's `status: ready` in the same edit:
     `unblock` never readies a blocked story with no dependency left. Make the edit as any board
     edit: through `swarm.sh board-pr` when the board is in the project's repo, where it is when it
     is outside.
   - `idle: "<project>"`: the step leaves the builders idle (`gate`, `done`, `escalated` or
     `release`), no story is one an agent can build, and there are findings to offer: up to five
     `out-of-scope finding: <date> <kind> <PR>: <text>` lines (findings declined as out of scope in
     the last 30 days and not yet filed, newest first). File one as a one-off story (through
     `swarm.sh board-pr`, or where the board is when it is outside the repo), then run
     `swarm.sh log-finding --filed --reviewer lead <kind> <PR> '<text>'` with the line's kind, PR
     and text, so `next` stops offering it; or tell the user why none fits. Later stories stay the
     user's to start, as the gate lists them. Declined out-of-scope findings are the swarm's list of
     follow-ups, so you need not keep them in memory.
2. Do the step:
   - `fix-main <slug>`: `swarm.sh merge` found CI on the base red on a commit it merged, printed
     `fix-main:` with the failed jobs' FAIL lines, and wrote the one-off story `<slug>` with them.
     `next` names this step only while `<slug>` is ready and nobody has started it. Merge nothing
     else until `<slug>` merges and the base is green, and never wait on an unrelated PR to fix it.
     If a conductor is still working (`swarm.sh status` lists one with no report), write a note
     telling it to start `<slug>` at once, ahead of every other story, send it with
     `swarm.sh tell <conductor> note <file>` (once: skip it if you already sent that note), and
     handle the step as `wait <conductor>`. Otherwise handle it as `story <slug>`. Once its build
     has started, `next` names the usual steps for it: `resume`, `wait`, or the gate with its PR
     waiting on a merge.
   - `no-agent <slug>`: the story's build started, but no agent works on it and no tell, wait-pr
     or merge is running for it. It is the line `wait --lead` prints as
     `no-agent: <slug>, exit: <exit>`, and `next` names it ahead of a conductor's wait so the wait
     cannot hide it. The why ends with the exit. A conductor may still be working behind this
     step: when `swarm.sh status` lists one with no report, start its watchers before the exit,
     `swarm.sh wait --until-report <conductor>` for each one and `swarm.sh wait --lead`, in the
     background, in the same response that read `next`. The exit can be a backgrounded wait-pr
     and then a merge, and the conductor must not go unwatched while they run. When one of those
     waits returns, act on it as `wait <agent>` says. Then run the exit as that line's handling
     under `wait <agent>` says: for a ready story, `swarm.sh restart <slug>` or
     `swarm.sh hold <slug> <reason>`; for one in review, the merge, review-agent or `gh pr list`
     the exit names, with `swarm.sh wait-pr <PR URL>` first only before the merge.
     `next` names each line once, so its next run goes on to the other steps even when the exit did
     not clear the story. If that leaves the story stuck, list it for the user
     with why. While a conductor works, `next` also starts conductors for other ready work and prints
     `started:` or `no conductor` lines after the why: handle them as under `wait <agent>`. Then go
     back to 1.
   - `wait <agent>`: a conductor is working. Run `swarm.sh wait --until-report <agent>` in the
     background, in the same response that read `next` and before any other work: a side task the
     user asks for meanwhile must not leave the conductor unwatched. It has no timeout. It returns
     once the conductor has written its report, is not idle (its session is waiting on a prompt, or
     gone), or prints `auth` or `stuck: ...`, not each time it idles on its own background work.
     `wait` nudges a conductor only to resume a turn that stopped on an API error. When it returns,
     go back to 1. Never
     close a conductor that has not reported.

     `next` itself starts a conductor for ready work that has none, and prints what it did after
     the why. A `started: <conductor> (swarm.sh conduct <arg>)` line is a conductor now working:
     `wait --until-report` it too. A line that begins `no conductor started:`, `no conductor for epic <e> started:` or
     `no backlog conductor started:` says why none did: a conductor that has reported (collect it
     first), a report nobody collected, an expired login or API error, another project's agent
     holding the name, a report newer than every story and epic file (the board must change
     first), or, under `merge = agent`, no allow rule for `swarm.sh merge` (the user adds the rule the
     line names). The backlog's can also say its report lists a story under `not started:` whose worktree
     is still there, so that build died: clear it first, as the line says. A `warning: ... failed`
     line means the start failed: run the `swarm.sh conduct` it names yourself once the cause is
     fixed. `warning: herdr cannot list its agents ...` means none was started because which
     conductors run is not known: check that herdr is running, then run `swarm.sh next` again. Delete a conductor's
     report yourself only when its pane is gone and you have read it, as `no conductor started:
     <conductor> is gone, and nobody collected <report>` says; `collect` closes the others.

     In the same response, also run `swarm.sh wait --lead` in the background. It returns when
     something new lands in your queue while the conductor works, one line per item. For a
     `held: <slug> (<cause>)` or `escalated: <slug>` line, do the `escalated <slug>` step for that slug at once, without waiting for `next`:
     `next` names the running conductor first and would not get to it. For a
     `merge: <slug> <PR URL>` line, tell the user the PR waits on their merge. A
     `kept: <slug> <PR URL>... (not reviewed)` line is a story whose builder was closed while its
     PRs were still open. It is in review, but its PRs are not offered to merge until
     `swarm.sh review <slug> <PR URL>...` marks them reviewed. While a conductor runs for the
     story's epic, as `swarm.sh status` lists them, leave the story to it: an epic's conductor
     reviews its kept stories under its merge rule. The backlog conductor's rule does not, so a
     kept story with no epic is yours at once. One you left to its conductor is yours at
     `collect`, when its report or `swarm.sh status` still lists the story as `kept:`. Either
     way, do the following for each PR on the line. Run
     `swarm.sh wait-pr <PR URL>` in the background, and on its exit 2 do as the `no-agent:` arm
     below says. Once it exits 0, compare the `head:` line of `.swarm/reviews/<slug>.md` with the
     head it printed: when they match, triage that file, and otherwise start a review with
     `swarm.sh review-agent <slug> <PR URL>`. From there, review the PR as a conductor does, by
     reference.md § Building (**Review before closing.**) and § The outer loop, logging every
     finding, fixed or declined, with `--round <n>`. Findings to fix, red checks, and a worktree
     review-agent refuses go to a builder. If none is open, start one in the story's worktree with
     `swarm.sh agent <tab> <slug> <worktree> <role> <brief>`, where <tab> is the story's `epic:`
     (its slug when it has none) and <role> is what `swarm.sh _role <slug>` prints. Its brief
     names the story and its PRs. Wait for it to go idle with `swarm.sh wait <slug>`. Send review
     findings with `swarm.sh tell <slug> findings <file>`, which counts the round and applies the
     ladder, and the rest with `swarm.sh tell <slug> nudge <file>`, which is not a round. Wait for
     the builder with `swarm.sh wait --stall <slug>` in the background, then run wait-pr and the
     review again on its new head. When that wait times out or stalls, or the builder goes idle
     with no new head, act as a conductor does by § Building (**Giving up on a builder.**). A
     `stuck:` line is not a stall: the `stuck:` rule below applies. Once every PR's latest head
     has passed, wait-pr exits 0 on it, and
     `swarm.sh findings <repo> <pr>` is triaged (§ The outer loop, **Green means more than green
     checks.**), close the builder if one is open (`swarm.sh close <slug>`). Then run
     `swarm.sh review <slug>` with every PR URL on the line: it keeps only the PRs it is given.
     That clears the line and hands the PRs on to merge. Under `merge = agent`, merge each yourself
     with `swarm.sh merge --head <sha> <PR URL>`, <sha> being the head its review passed on. When
     merge refuses one as held for the user (`costs: money`, or a parent they merge), tell the user
     it waits on their merge. Run `swarm.sh close <slug> --drop`
     only when the PRs are not worth saving. It counts the attempt, so the next build may move up a
     model or the story may become yours, then closes the PRs and sends the story back to ready. A
     `no-agent: <slug>, exit: <exit>` line means a story whose build started has no agent on it
     and no tell on the way. Run the exit it names. For a ready story it is
     `swarm.sh restart <slug>`, which starts its builder again in its worktree (named only while that worktree is there), or
     `swarm.sh hold <slug> <reason>` when it should wait, saying why. A hold only answers the line: if no
     agent is back by the next poll, it comes back. For a story in review under `merge = agent`
     it is `swarm.sh merge --head <sha> <PR URL>`, or `swarm.sh review-agent <slug> <PR URL>` when
     no single reviewed head is known. Before that merge, run `swarm.sh wait-pr <PR URL>` in the
     background and act on its exit, not on the line, once per head. On 0, compare the head it
     printed with the `<sha>` in the exit: the same, run the merge; different (pushed since the
     review), run `swarm.sh review-agent <slug> <PR URL>` instead. On 1
     (red), start a builder in the story's worktree (`swarm.sh agent`) with a brief naming the
     failing checks, or, if you leave it, list it in your report with the reason:
     `swarm.sh hold` takes only a ready story. On 2, read why it printed: on a conflict with the
     base, have a builder in the story's worktree merge the base in and push; on a gh error or
     the timeout, run wait-pr once more, and if it ends the same way, list the story in your
     report with the reason. With no PR URL on the story, find its PR with the
     `gh pr list -R <repo> --head story/<slug>` the exit names, and run the review-agent exit. The line is quiet while
     wait-pr runs and may come back once after it ends; that needs nothing new. A
     `no-review: <slug> <PR URL>, exit: swarm.sh review-agent <slug> <PR URL>, or the fallback reviewer`
     line means the PR's review agent never started, or started and went without findings for its
     head, and no review round is under way. It comes even while the builder works. Run
     `swarm.sh review-agent <slug> <PR URL>`. Once `review-<slug>` is open, the next poll is quiet.
     If it fails again, its `review-agent <slug>` line in `.swarm/events.tsv` says why. A worktree
     not at the PR's head, or with uncommitted changes, means the builder is still at work: leave it,
     and the conductor starts the review once it pushes. If no review agent can start, review the
     PR yourself with codex-review (the exit's `or the fallback reviewer`), but only while the
     story's worktree is at the PR's head (`gh pr view <PR URL> --json headRefOid`) with nothing
     uncommitted, as review-agent checks. codex-review reviews the directory it runs in, so run it
     from the story's worktree (`<repo>-wt/<slug>`, beside its repo), in the background:
     `cd <repo>-wt/<slug> || exit 1 && SWARM_STORY=<slug> SWARM_PROJECT=<this project> swarm.sh codex-review <base>`
     (`swarm.sh base <repo>` prints the base). It runs codex, or at codex's usage limit the model
     `fallback_reviewer` names. Write its findings to a file and send them with
     `swarm.sh tell <slug> findings <file>`: that tell is a round under way, and the line goes quiet.
     If it finds nothing, send that to the story's conductor instead with
     `swarm.sh tell <conductor> note <file>`, under the name `swarm.sh status` lists for the story's
     epic or for the backlog. A clean run of yours clears nothing: the line stays in `status` and on
     the dashboard until a review agent starts on the PR, findings go to the builder, or the PR
     merges and the story leaves the board.
     A line with no PR URL names a `gh pr list` that finds the PR first. A
     `step-up failed: <slug>, exit: swarm.sh step-up --resume <slug>` line means a step-up closed
     the story's builder and then could not start the next model's. Its conductor leaves the story
     alone, so it is yours. The `step-up:failed` line in `.swarm/events.tsv` says where it stopped,
     and sometimes why. The error is in the output of whatever ran the step-up: read that output
     in every case before you resume. For a step-up swarm.sh ran itself, it is the
     conductor's pane: `herdr agent read <conductor>`, the name `swarm.sh status` lists for the
     story's epic or for the backlog. For one run by hand, it is the command's own output. With
     no `step-up:failed` line, the step-up was killed partway. Fix the cause the output shows,
     then run the exit. A pane may still be open under the builder's name, kept by the failed
     start or left by a killed step-up. The resume retires an idle agent in it and starts the
     rung (`swarm.sh tidy` closes the retired pane), and refuses while that agent is working or
     waiting, naming it: read it with `herdr agent read <agent>`. A working one took up its
     brief, so do not resume again: tell the user, since no swarm.sh command records that rung.
     One waiting on a question gets its answer there, then the resume again. If you cannot fix
     the cause, tell the user. An
     `unsent brief: <stem>, exit: <exit>` line means an agent sat idle with its brief still in its
     input box after `wait --lead` had pressed Enter on it once. `<stem>` is the slug for a builder,
     `review-<slug>` for a review agent and `conduct-<epic>` for a conductor. Run the exit. For the
     builder of a ready story it is `herdr pane close <pane>`, then the restart a `no-agent:` line
     would name. Do not use `swarm.sh close` on a builder: it counts a failed attempt and clears the
     worktree that restart needs. A builder whose story is not ready, such as one in review with its
     findings in the box, is kept: the exit is `swarm.sh tell <slug> nudge <file>`, the file asking
     it to act on the brief in its input box. For a review agent the exit is `swarm.sh close review-<slug>`, then
     `swarm.sh review-agent <slug> <PR URL>`, and for a conductor `swarm.sh close conduct-<epic>`,
     then `swarm.sh conduct <epic>`. Then start
     `wait --lead` again. The conductor's `wait --until-report` keeps running throughout. If
     `wait --lead` times out (non-zero, nothing printed), start it again. Only one runs at a
     time: a new one stops the earlier one, which then ends with nothing printed; that needs
     nothing from you. A new run first reports anything that landed while none was running.

     Once both waits are running, send each
     `queued: <repo> #<n> <branch> green <m>m with no review on <sha> (<conductor>)` line after the why
     to the conductor it names: write the line to a file and run `swarm.sh tell <conductor> note <file>`.
     That PR has been green and mergeable for `queue_minutes` with no review agent on that head, and
     the note tells the conductor to start its review now. `tell` records the head as sent, and `next`
     leaves out a head already sent (by you, or by the conductor's own `watch`), so each line comes once.
     `next` prints these lines after the why of any step while conductors work (a `collect` or
     `plan-epic` too, one line per PR of every working conductor): send them the same way.

     Then take each `also: lead <slug> blocks <slugs>` line after the why
     and run that lead story while the wait runs: the stories it names stay blocked until it is
     done, and no conductor builds it. Tell the user, as the gate does, that you will run it once
     they say go, with its **You:** steps. Once it is done, run `swarm.sh finish <slug>` and land
     the board PR it opens as above: `swarm.sh merge --board <url>`, or with `merge = human` hand
     it to the user and wait until they merge it, unless `swarm.sh grants <url>` lists `merge` for
     it, which lets you run the merge (a `costs: money` PR, or one stacked on one, stays the
     user's, grant or not). Then run `swarm.sh reconcile`, and leave
     `swarm.sh unblock` to the conductor: after each wait it runs `swarm.sh unblock --startable`
     and builds every ready story of its own with no build yet. Act on each `also:` story once. It stays `ready`, and
     `next` names it again, until its `finish-<slug>` board PR merges, so skip one you have
     already asked about or run, or whose finish PR is open.

     If any `wait` here or below prints `stuck: api error` (exit 4: the agent's turn stopped on an
     API error three times in a row, and `wait` already told it to carry on each time) or `stuck: no
     output for <N>m (<pane>)`, read the pane (`herdr agent read <agent>`), tell the user what it
     shows, and stop for them.

     If any `wait` here or below prints `auth`, the agent it names stopped on "Login expired ·
     Please run /login". No agent can fix that, and only the user's `/login` clears it. Stop, and
     tell the user to run `/login` and nothing else. Once they say it is done, write a file
     that says "Your login is renewed: resume where you stopped. Send the same to any builder whose
     wait printed auth." and run `swarm.sh tell <agent> resume <file>` for each agent whose `wait` printed
     `auth`, then go back to 1.
   - `collect <agent>`: the conductor has finished. Fetch the project's repo (`git fetch`), then run
     `swarm.sh outcomes --since <the day 30 days ago, YYYY-MM-DD>` (the window keeps its gh calls to
     recent builds; the `recurring` block counts its own last 30 days either way) and read its
     `recurring` block. For each kind there with an empty `check` column, file one story with
     `checks: <kind>` in its front matter that adds a test, lint rule, hook or review-prompt line
     which catches that kind, like any board edit: through `swarm.sh board-pr` named `check-<kind>`
     when the board is in the project's repo, or written where the board is when it is outside.
     Skip the kind when a story on the board already has `checks: <kind>`, or, with the board in the
     repo, when `gh pr list -R <owner/repo> --state all --head board/check-<kind> --json state,closedAt`
     (the project's origin, as `git remote get-url origin` names it) shows one `OPEN` (pending),
     one `MERGED` (its story is on the board, or about to be, since collect only fetches), or one
     `CLOSED` (unmerged) in the last 90 days, which means the user declined it. A board outside the
     repo has no PR to look up, and its merged story leaves no git deletion to fill `check`, so
     after filing a story there append a line (the kind, a tab, today as YYYY-MM-DD) to
     `.swarm/checks-filed.tsv` (the project's, a path relative to it), and skip
     any kind already listed in that file.
     A kind whose check has merged (`check_merged` set) still recurs once its fixes after the merge
     reach 3 PRs: while the check is under 30 days old that is `since_30d`'s `<n>` (it reads
     `<n>/<days>d`); from 30 days on, every PR in the block's rolling `prs_30d` came after the merge,
     so being listed is enough. Then tell the user, with `before_30d` and that count. Then read its report
     (`.swarm/conduct-<epic>.report.md`), relay what merged, what
     is left and what waits on the user, then `swarm.sh close <agent>`.
   - `conduct <epic>`: `swarm.sh conduct <epic>`, then handle it as `wait conduct-<epic>`. When it
     (or the story step's `swarm.sh conduct --backlog`) stops with `no conductor started: merge = agent
     and no allow rule for swarm.sh merge ...`, adding that rule is the user's step: tell them the rule
     and the files the line names, then stop.
   - `resume <slug>`: a one-off that an earlier run started (its worktree exists). If the last
     `.swarm/conduct-backlog.report.md` lists `<slug>` under `not started:` (a build that died
     leaves a worktree with no builder and no PR), start no new conductor: `next` names it again for
     as long as the worktree is there. Tell the user why it could not start, name its worktree
     (`../<repo>-wt/<slug>`, beside its repo), and say what clears this stop. First, if
     story/<slug> has commits worth keeping (`git log origin/<base>..story/<slug>` in its repo,
     where `swarm.sh base <repo>` prints the base), push it and open a PR from it instead. Otherwise
     the build's work is discarded: from the repo, `git worktree remove --force ../<repo>-wt/<slug>`,
     `git worktree prune` and `git branch -D story/<slug>`, and `git push origin --delete
     story/<slug>` if it was pushed; then delete `.swarm/conduct-backlog.report.md`. Then stop.
     Otherwise handle it as `story <slug>`, which runs `swarm.sh conduct --backlog`: the backlog
     conductor waits on a story whose worktree exists, and never starts it again.
   - `story <slug>`: a one-off (a ready story with no `epic:`). The backlog conductor builds every
     one-off as a conductor builds an epic: it reviews each PR, and hands it to the user or merges
     it as `swarm.sh config merge` says. If `.swarm/conduct-backlog.report.md` exists and no story
     or epic has been added, changed or removed since it was written (`find <board>/stories
     <board>/epics \( -name '*.md' -o -type d \) -newer .swarm/conduct-backlog.report.md` prints
     nothing; a directory is listed when a file in it was removed), the last backlog conductor
     stopped on the board as it is now, and a new one would stop the same way, whatever the report
     says: start no new conductor. Tell the user why `<slug>` is still waiting (its `not started:`
     line, or what the report says is left: CI on the base red or timed out, a story escalated to
     the lead), show what `swarm.sh status` lists under Waiting on you, and say what clears this
     stop: a story or epic added, changed or removed (a merge removes one), or, for a fix that
     touches neither (a code PR that turns CI on the base green), deleting
     `.swarm/conduct-backlog.report.md` once the cause is fixed. Then stop. Otherwise run
     `swarm.sh conduct --backlog`, then handle it as `wait` on the conductor it started
     (`conduct-backlog-<dir>-<hash>`; `next` prints the name).
   - `stage v<S>`: a tag at or above the minor before v<S> is on the base, and the draft epics `next`'s why
     names carry `stage: v<S>` and an `hld:` naming an agreed HLD that grants `epics`, so they go
     active with no agreement from the user. The board PR is named `stage-v<S>` with the dots as
     dashes (v0.30.0 gives `stage-v0-30-0`). Open it: `swarm.sh board-pr start <name>`, set each
     named epic's `status: active` there and change nothing else, then `swarm.sh board-pr open <name>
     "Start stage v<S>" <body-file>`, its body naming the epics and the tag. Run `swarm.sh wait-pr
     <url>` in the background and wait for it; if it does not exit 0, tell the user what it printed
     and stop. Land it with `swarm.sh merge --board <url>` when `swarm.sh config merge` prints
     `agent` or `swarm.sh grants <url>` lists `merge`, then go back to 1. Otherwise hand the PR to
     the user: the `epics` grant lets you set the epics active, not merge the PR. If merge refuses,
     stop and tell the user what it printed. Under `merge = human` with no `merge` grant, the user
     says not yet by leaving the PR unmerged: `next` names no new stage PR while it is open. An
     epic leaves the stage when its `stage:` or `hld:` is dropped. Tell the user both as you hand
     them the PR, then go back to 1. For as long as the PR's worktree exists, `next` goes on to the
     steps after this one, and the gate, `status` and `dash` list `stage PR awaiting merge: v<S>`,
     whether its epics are still drafts or the merge has made them active. On that line, finish the
     edit first, since a run that stopped between the edits left some of the stage's epics drafts:
     every draft epic in the worktree that carries `stage: v<S>` and an `hld:` naming an agreed HLD
     that grants `epics` gets `status: active`. Then run the `board-pr open` line once more: it
     prints the PR's URL, the one already open or a new one, and tells the branch's own PR from an
     earlier use of the name. When it says the PR on the branch has merged or closed, or that the
     worktree changes nothing, run `swarm.sh board-pr done <name>`, so a later draft of the same
     stage is not held behind the worktree, and go back to 1: after a PR closed without merging,
     `next` names `stage v<S>` again and you open a new one. On any other failure, stop and tell
     the user what it printed. With a URL, under `merge = agent` or a `merge` grant, run `swarm.sh
     wait-pr <url>` in the background, wait for it, and land it with `swarm.sh merge --board <url>`
     when it exits 0, then go back to 1; if it does not, or merge refuses, tell the user what it
     printed and stop. Under `merge = human` with no `merge` grant, it is the user's: stop.
   - `plan-epic <epic>`: follow `/plan-epic <epic>`. When it asks the user to approve the stories,
     that is the user's decision: stop and wait for it. On approval, finish the command and go on.
     When its why says a `later` epic's dependencies are done (offered before the gate), run it
     unasked: planning is read-only. First run `swarm.sh plan-unasked <epic>`, so `next` offers it no more:
     the gate lists it as planned unasked, and with no stories yet says to run `/plan-epic <epic>`
     again if that plan stopped (a login expired, a pane closed). If the user declines it,
     run `swarm.sh plan-unasked --declined <epic>`, so the gate says that instead. Approving its stories stays the user's, unless the user named
     the epic as pre-approved (in the brief or in chat). Its stories, or its child epics (kept
     `later`), then wait in the gate until the user starts it.
     When `next`'s why names a conductor that is still working, start
     `swarm.sh wait --until-report <conductor>` in the background first, so it stays watched while
     you plan.
   - `plan-hld <hld>`: follow `/plan-hld <hld>`. Approving its epics is the user's decision: stop
     and wait for it, unless `swarm.sh grants <hld>` lists `epics`, which lets it write them active
     and open the board PR unasked. Its board PR lands like any other: the HLD's `merge` grant
     covers it under `merge = human`. Once that PR has merged or been closed, run
     `swarm.sh board-pr done plan-<hld>` and `swarm.sh close plan-<hld>`, so an abandoned worktree
     never hides the HLD from `next` and its agents' tab closes.
     When the gate lists `plan PR awaiting merge: <hld>` and no PR is open on `board/plan-<hld>`,
     run `/plan-hld <hld>` again: it clears the worktree of a plan PR that merged or closed, and
     resumes in one that stopped before `board-pr open`.
   - `hld <hld>`: every epic planned from the HLD has left the board. Run `swarm.sh finish <hld>`.
     Under `merge = agent`, merge the PR it opens with `swarm.sh merge --board <url>`, as any board
     PR; under `merge = human`, hand it to the user: the finish PR is then the user's, grant or not.
     Once that PR has merged or been closed, run `swarm.sh board-pr done finish-<hld>`, so an
     abandoned worktree never hides the HLD from `next`. When the gate lists
     `finish PR awaiting merge: <hld>`, read the PR (`gh pr list --head board/finish-<hld> --state all
     --json url,state`): once it has merged or closed, run `swarm.sh board-pr done finish-<hld>`;
     while it is open, it is the user's under `merge = human`, and yours to merge under `merge = agent`.
   - `escalated <slug>`: Fable's build of the story failed too, or its builder called it impossible
     (its block starts **Impossible.**): no Fable build failed then, the judge called its **Done
     when** impossible, and that **Done when** is what to re-scope. Or a close held it (`held_for:`,
     its block starts **Held (<cause>).**, and `next`'s line names the hold): its builder paused or
     its goal was cleared on an error, nothing failed, and there is nothing to re-scope. A top-rung
     hold (`held_for: top-rung`) is the exception: its builder on or above the ladder's top rung kept
     drawing findings, so narrow the scope to something that fails closed, split the story, or accept
     the PR with follow-ups, then lift the hold and send the kept builder the findings file its block
     names (`swarm.sh tell <slug> findings <file>`). To drop it instead, close its builder, PR and
     worktree first, as its block says. Deciding what happens to it is
     yours, not the user's, so this is not a stop. Read the story, its block (`.swarm/escalated/<slug>`) and the attempts'
     PRs it lists, with their review findings. Then decide on the spot, and tell the user in a line
     or two what you chose and why:
     - A held story: lift the hold with `swarm.sh reset <slug> <reason>`, which puts its kind back
       and keeps `attempts:`, so it is built again. Lifting a hold is not the story's one reset, so
       the at-most-once rule below does not apply to it. Or drop it, as below.
     - Re-scope it: change the story so a fresh build can succeed, and run
       `swarm.sh reset <slug> <reason>`. When the board is in the story's repo, a builder reads the
       story in its own worktree, from the branch builds start from, so the new scope has to reach
       that branch first: make the change in a board PR (`swarm.sh board-pr`) and leave the main
       checkout's copy alone.
       Once that PR has merged, run `swarm.sh reset <slug> <reason> && git pull --ff-only` in
       the board's repo, in one go: `reset` puts the file back to its committed text, so the pull
       brings in the re-scope (its kind, repo, epic and risk included) before anything builds it.
       Until the PR merges, `next` names the story again: that is a wait on the user's merge,
       so name the board PR, show what `swarm.sh status` lists under Waiting on you, and stop.
       A story is reset at most once (`reset` refuses a second, and `next` then says to drop it),
       so after its second failed escalate build, drop it.
     - Drop it: `swarm.sh drop <slug> <reason>` deletes it from the board, in the board PR
       `drop-<slug>` when the board is in the repo. With `merge = agent`, land that PR with the
       `swarm.sh merge --board` line it prints. With `merge = human` you never merge: hand the PR
       to the user, unless `swarm.sh grants <url>` lists `merge` for it, which lets you land it
       as above; a `costs: money` PR, or one stacked on one, stays the user's, grant or not. Until the PR merges, `next` names the story again: that is a wait on the
       user's merge, so name the board PR, show what `swarm.sh status` lists under Waiting on
       you, and stop.

     Then go back to 1.
   - `release`: the base has changes since the last release tag (`next`'s why names both), so cut
     a release. A stage release is a minor: cut it only when `next` prints `release v<S>`, and make
     `<new>` that number without the `v` (`release v0.28.0` gives 0.28.0). For
     `release v<x.y.z+1> (patch)`, `<new>` is likewise the number alone, without the `v` and without
     ` (patch)` (0.28.1, never `v0.28.1 (patch)`). While `next` prints a
     `release-held:` line, cut no minor: cut only the patch `next` names, if it names one. `merge --release` does not read the hold, so only this step keeps
     it. If a PR from a `release/v<new>` branch is open, use it. Otherwise, ship the docs
     first: list the behaviour changes since the tag (`git log v<version>..origin/<base>`), and unless docs
     merged since the tag cover them, land a docs PR that covers each one in README.md, AGENTS.md, docs/reference.md, docs/method.md and
     commands/*.md as they apply, its prose run through the humanizer skill. It reaches the
     base the way a fix does, through a `kind: code` story or a lead PR; stop there, and
     go back to 1 once it is on the base. Then make a worktree
     of a new branch `release/v<new>` from `origin/<base>`, and in it bump only
     `.claude-plugin/plugin.json`, to `<new>`: the version `next`
     named, either the stage's v<S> or the patch it named. Only when `next` printed a bare `release`,
     bump to the next minor version (a patch when every change since the tag is a fix). Commit with the brief's trailers, push, and open the PR titled
     `Release v<new>`, listing the PRs merged since the tag and naming the docs PR. For swarm-dev's own repo, the body also
     lists the behaviour changes every project gets on upgrade and names the infrafactory build they
     were tried on, or says none. When nothing
     since the tag changes what a user runs, sees or has to do, skip the docs PR and put a
     `Docs: none — <reason>` line in the release PR body instead: `merge --release` refuses a
     release whose `bin/`, `commands/` or `hooks/` changed since the tag while README.md, AGENTS.md
     and docs/ did not, unless that line is there (a change only to commands/*.md counts as its own
     docs). Run `swarm.sh wait-pr <PR URL>` in the
     background and wait for it. If it exits 1, a check is red. A release PR may change only the
     version, so `merge --release` refuses one with a fix on it: the fix goes to the base through a
     story or a lead PR, then close this PR and cut the release branch again from the base's latest
     green commit. Stop there, and go back to 1 once the fix is on the base. If it exits 2, gh failed, no checks appeared or they never finished: tell the user
     what it printed and stop. Run
     `swarm.sh merge --release --head <its head SHA> <PR URL>` in the background and wait for it,
     under `merge = human` too: there it merges only when HLDs granting `release` cover the release.
     Then go by whether merge printed `merged:`, not by its exit code:
     - It printed `merged:`, even if it then exited non-zero (red CI on the base also printed `fix-main:`
       and wrote a story; a CI timeout wrote none): tell the user what it printed. For swarm-dev's own
       repo, merge has confirmed the tag and the GitHub release, updated the
       plugin and started the agents' upgrade: tell the user its restart line (`/exit`, then
       `claude --continue`) and any warning it printed. If CI on the base was not green, merge
       updated nothing and printed a warning naming what to run once the release is published:
       tell the user that warning. If it printed `warning: ... ships <commits> unchecked` (or that gh
       cannot read the merge commit's parent), a PR landed between the release check and the merge,
       in any repo: tell the user those commits shipped in the release unchecked. For swarm-dev's
       own repo merge then updated nothing and printed `refused: ...`: tell the user what that line
       says to run. For any other repo, check that the tag
       `v<new>` exists and that `gh release view v<new>` shows the release. If merge instead printed
       `<url> is MERGED, not open` (the user merged it) or `unconfirmed (...)` and `gh pr view` shows
       it MERGED, merge stopped before it waited for CI on the base or ran the upgrade: look at CI on
       the base yourself, check the tag and the release, and tell the user the plugin update did not
       run. Then run `swarm.sh dash --check`, which compares every figure dash shows with the command
       that owns it and exits 1 naming each one that differs. If it fails, run it once more, since a
       figure can move between the two reads; if it fails again, file a `kind: code` story naming the
       fields it printed. Remove the worktree and the branch, and go back to 1.
     - It refused because of the PR: a version not greater than the base's, more changed than the
       version, a fix on it, a missing docs PR or `Docs: none` line, a head that moved, or a PR that is
       CLOSED. The lead acts, under both settings: do what the refusal says (a fix or the docs goes to
       the base first, as above; merge origin/<base> into the PR; or remove this worktree and the
       `release/v<new>` branch, close the PR and cut the release again). Run `swarm.sh dash --check` as
       above, then stop and go back to 1 once that is done.
     - Any other refusal: under `merge = human` the release-grant refusal ("waits on the user's merge"),
       a merge queue, a failed fetch of the base, a missing `v<version>` tag, a gh error. Keep the
       worktree and the branch. Run `swarm.sh dash --check` as above. Tell the user what the refusal
       printed and that the PR waits on their merge, show what `swarm.sh status` lists under Waiting on
       you, and stop. Under `merge = agent` that holds for the merge-queue refusal and a missing tag,
       which only the user clears; for any other refusal, tell the user what it printed and stop.
   - `gate`: show the list `next` printed and, for each item, what the user must do (a lead
     story: that you will run it once they say go, and its **You:** steps; a story of any other
     kind: that its `kind` is wrong and must be fixed on the board; a blocked
     story: what blocks it; a later story or epic: set it `ready` or `active` to start it; a draft epic:
     only the user agrees it, through /epic, which writes `agreed:` as it sets `status: active`.
     The lead sets a new or draft epic `active` itself only when no agreement is needed: it has a
     `parent:` (a split's child), an agreed HLD grants `epics` through its `hld:`, or
     `lead_epics = on` in `.claude/swarm/config`. An `agreed:` already on a draft is stale (an epic
     set back to draft by hand) and does not count. Offer to follow `/epic <slug>` to resume it,
     which opens the co-author's pane and picks up the review and the agreement in the background; a PR
     awaiting your merge: merge it, or close it to send the story back to `ready`). An escalated
     story is never in that list: it is yours, and `next` names it first. A staged epic
     (`staged epic: <slug>, stage v<T>, after v<P>`) needs nothing from the user: `next` names
     `stage v<T>` once the base has a tag at or above v<P>, and you set it active then. A `stage PR awaiting
     merge: v<T>` line is the stage arm's PR: handle it as that arm says, which may go back to 1.
     Otherwise stop.
   - `done`: say so and stop. If this finds no file (`find <board>/epics <board>/stories
     -maxdepth 1 -name '*.md' ! -name README.md`), the board is empty, not finished: explain the flow in
     about five lines (an epic written with you, split into stories, built by
     agents in panes, and where it stops for you: approvals, `lead` stories, merges) and suggest
     `/epic <title>`. Otherwise suggest `/epic <title>` for the next piece of work.
3. Go back to 1. Every step changes the board (a merge, a new file, a status), so `next` moves on;
   if it prints the same step twice in a row with nothing changed, stop and report why.

Log every time a person had to step in, the moment it happens, so `swarm.sh flow` and `swarm.sh dash`
count it:

- `swarm.sh intervene lead-hand "<what you did>"` when you acted by hand where a command should
  have (you typed into a stalled agent's pane, merged or edited something yourself).
- `swarm.sh intervene user-caught "<what they found>"` when the user found a problem before the
  swarm did (held stories or a slow CI run they found by asking).

Never skip an approval to keep the loop going, never merge red, never merge at all when `merge`
is `human` unless `swarm.sh grants <PR URL>` lists `merge` for the PR, and then only with
`swarm.sh merge <PR URL>` (not `gh pr merge`, not `gh api`, not the web page). Without that grant
the user merges it, even when they ask you to, since `swarm.sh merge` refuses it. A release PR is the user's too, unless `swarm.sh merge --release`'s release check finds that an
HLD granting `release` covers every story merged since the last tag. A `costs: money` PR, or one stacked on one,
is the user's to merge whatever the grant says. Never give a `lead` story to an agent.
Stopping is safe: the next `/swarm-dev:swarm` reads the board and continues.

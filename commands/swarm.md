---
description: Start here. Runs the whole chain from wherever it stands (HLD, epics, stories, builds), stopping only where the user must decide
---

The board is the directory `swarm.sh config board_dir` prints (`docs/` unless the project's
`.claude/swarm/config` says otherwise); every `docs/hld/`, `docs/epics/` and `docs/stories/` below
is inside it.

Drive the chain end to end, picking up wherever the board says it stands. Requires herdr
(`HERDR_ENV=1`); if not inside herdr, say so and stop. Read `${CLAUDE_PLUGIN_ROOT}/docs/method.md`
first if you have not this session.

If `<board>/stories/README.md` does not exist, the project has no board yet. Offer to run
`swarm.sh init` from the project's git root, and wait for the user's yes before you run it. It adds
the board, `.claude/swarm/` and the `.gitignore` lines, then tells the user to run `claude` there once
and accept the folder trust prompt. Only the user can do that, so stop after it.

If `.claude/swarm/brief.md` does not exist, ask the user once, in one message, for their commit
trailers, where credentials live, and commands that must never run. Write only what they said to
`.claude/swarm/brief.md`, under 4 KB (`BRIEF_MAX_BYTES`). If they decline, write an empty file so they
are not asked again. Do not commit it. Tell the user to commit it, even empty: an untracked brief
stops `swarm.sh reconcile` from pulling a `lesson:` PR that adds the file.

When the board is in the project's repo, make each board edit you write by hand (a re-scope, a new
story, an unblock) in its own worktree with `swarm.sh board-pr`, never in the main checkout. A board
outside the repo is edited where it is, since `board-pr` refuses it.

`swarm.sh board-pr start <name>` prints the worktree's path, `<repo>-wt/_board-<name>` (beside the
story worktrees, never one of them), on a new `board/<name>` branch from origin's base. Edit the
board there, then run `swarm.sh board-pr open <name> "<title>" <body-file>`. It refuses if anything
outside the board changed, and otherwise commits with the brief's trailers, pushes and prints the
PR's URL. Run it again to push more edits to the same PR. Once the PR has merged or closed, `open`
refuses, and `swarm.sh board-pr done <name>` removes the worktree and the branch, here and on origin;
run `start` again for the next edit. `done` also clears a start you abandoned with nothing committed.

First run `swarm.sh version`. If it prints a WARNING, show it to the user word for word, then carry on:
an old version still runs.

Repeat until a step below says stop:

1. Run `swarm.sh reconcile` (it takes off the board what you merged, and puts back to `ready`
   what was closed unmerged), then `swarm.sh unblock` (it readies stories whose blockers have
   merged), then `swarm.sh next`.
   Its first line is the step, the rest is why. Tell the user both in one line.
2. Do the step:
   - `wait <agent>`: a conductor is working. Run `swarm.sh wait --until-report <agent>` in the
     background, in the same response that read `next` and before any other work: a side task the
     user asks for meanwhile must not leave the conductor unwatched. It has no timeout. It returns
     once the conductor has written its report, is not idle (its session is waiting on a prompt, or
     gone), or prints `auth`, not each time it idles on its own background work. `wait` never
     nudges a conductor. When it returns, go back to 1. Never
     close a conductor that has not reported.

     If any `wait` here or below prints `auth`, the agent it names stopped on "Login expired ·
     Please run /login". No agent can fix that, and only the user's `/login` clears it. Stop, and
     tell the user to run `/login` and nothing else. Once they say it is done, write a file
     that says "Your login is renewed: resume where you stopped. Send the same to any builder whose
     wait printed auth." and run `swarm.sh tell <agent> resume <file>` for each agent whose `wait` printed
     `auth`, then go back to 1.
   - `collect <agent>`: the conductor has finished. Fetch the project's repo (`git fetch`), then run
     `swarm.sh lessons`. For each `candidate`, look for an earlier rule PR first
     (from the project's repo, `gh pr list --state all --limit 200 --search 'in:title "lesson: <kind>"'
     --json title,state,closedAt`, keeping only a title exactly `lesson: <kind>`): an open one is pending, and one closed
     unmerged (its `closedAt`) in the last 90 days means the user declined it; in either case propose
     nothing. A merged one does not block: `lessons` lists a kind only while neither the brief nor `lessons_file` has a rule
     for it, so the rule was since removed. Otherwise
     draft one rule (under 300 bytes, on a single line, ending in `<!-- lesson: <kind> -->`: the briefs
     paste only the tagged line; for a candidate from the
     lead's memory, from that memory, generalised, with nothing private from it; if the user closes
     that PR, remove the memory's `lesson:` line, or it is proposed again after 90 days) for the file
     `swarm.sh config lessons_file` prints (the brief unless the project chose, say, `AGENTS.md`) and open it as a PR titled `lesson: <kind>`, never committed silently.
     For a `long brief` (the brief, plus `lessons_file`'s tagged rules when it says so), propose merging or
     retiring rules in whichever file holds them as a PR titled exactly `lesson: prune brief`,
     unless one is open or was closed (its `closedAt`) in the last 90 days; for a `recurring` kind, say so to the user. Then read its report
     (`.swarm/conduct-<epic>.report.md`), relay what merged, what
     is left and what waits on the user, then `swarm.sh close <agent>`.
   - `conduct <epic>`: `swarm.sh conduct <epic>`, then handle it as `wait conduct-<epic>`.
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
     `swarm.sh conduct --backlog`, then handle it as `wait conduct-backlog`.
   - `plan-epic <epic>`: follow `/plan-epic <epic>`. When it asks the user to approve the stories,
     that is the user's decision: stop and wait for it. On approval, finish the command and go on.
     When `next`'s why names a conductor that is still working, start
     `swarm.sh wait --until-report <conductor>` in the background first, so it stays watched while
     you plan.
   - `plan-hld <hld>`: follow `/plan-hld <hld>` the same way; its approval is the user's too.
   - `hld <hld>`: the HLD is a draft, and only the user can write it. Follow `/hld` to resume it
     (the title is in the file): the user works in the co-author's pane, and the review and the
     agreement are picked up in the background. Go back to 1 once `/hld` reports it agreed.
   - `escalated <slug>`: Fable's build of the story failed too, or its builder called it impossible
     (its block starts **Impossible.**): no Fable build failed then, the judge called its **Done
     when** impossible, and that **Done when** is what to re-scope. Or a close held it (`held_for:`,
     its block starts **Held (<cause>).**, and `next`'s line names the hold): its builder paused or
     its goal was cleared on an error, nothing failed, and there is nothing to re-scope. Deciding what happens to it is
     yours, not the user's, so this is not a stop. Read the story, the block at its end and the attempts'
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
     - Drop it: `swarm.sh drop <slug> <reason>` deletes it from the board; open a board PR with
       the change.

     Then go back to 1.
   - `release`: the base has changes since the last release tag (`next`'s why names both), so cut
     a release. If a PR from a `release/v<new>` branch is open, use it. Otherwise, make a worktree
     of a new branch `release/v<new>` from `origin/<base>`, and in it bump only
     `.claude-plugin/plugin.json`, to the next minor version (a patch when every change since the
     tag is a fix). Commit with the brief's trailers, push, and open the PR titled
     `Release v<new>`, listing the PRs merged since the tag. Wait for its checks in the
     background. If `swarm.sh config merge` is `agent`, run
     `swarm.sh merge --release --head <its head SHA> <PR URL>` in the background and wait for it.
     Then check that the tag `v<new>` exists and that `gh release view v<new>` shows the release,
     remove the worktree and the branch, and go back to 1. If it is `human`, tell the user the PR
     waits on their merge, show what `swarm.sh status` lists under Waiting on you, and stop.
   - `gate`: show the list `next` printed and, for each item, what the user must do (a lead
     story: that you will run it once they say go, and its **You:** steps; a story of any other
     kind: that its `kind` is wrong and must be fixed on the board; a blocked
     story: what blocks it; a later story or epic: set it `ready` or `active` to start it; a PR
     awaiting your merge: merge it, or close it to send the story back to `ready`). An escalated
     story is never in that list: it is yours, and `next` names it first. Stop.
   - `done`: say so and stop. If this finds no file (`find <board>/hld <board>/epics <board>/stories
     -maxdepth 1 -name '*.md' ! -name README.md`), the board is empty, not finished: explain the flow in
     about five lines (a design written with you, split into epics, split into stories, built by
     agents in panes, and where it stops for you: approvals, `lead` stories, merges) and suggest
     `/hld <title>`. Otherwise suggest `/hld <title>` for the next piece of work.
3. Go back to 1. Every step changes the board (a merge, a new file, a status), so `next` moves on;
   if it prints the same step twice in a row with nothing changed, stop and report why.

Never skip an approval to keep the loop going, never merge red, never merge at all when `merge`
is `human` unless the user asks you to merge a PR, and then only with `swarm.sh merge <PR URL>`
(not `gh pr merge`, not `gh api`, not the web page), and never give a `lead` story to an agent.
Stopping is safe: the next `/swarm-dev:swarm` reads the board and continues.

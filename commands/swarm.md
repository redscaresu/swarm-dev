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

First run `swarm.sh version`. If it prints a WARNING, show it to the user word for word, then carry on:
an old version still runs.

Repeat until a step below says stop:

1. Run `swarm.sh reconcile` (it takes off the board what you merged, and puts back to `ready`
   what was closed unmerged), then `swarm.sh unblock` (it readies stories whose blockers have
   merged), then `swarm.sh next`.
   Its first line is the step, the rest is why. Tell the user both in one line.
2. Do the step:
   - `wait <agent>`: a conductor is working. Run `swarm.sh wait <agent>` in the background, in
     the same response that read `next` and before any other work: a side task the user asks
     for meanwhile must not leave the conductor unwatched. For a conductor it returns once
     the conductor has written its report, is not idle (its session is waiting on a prompt, or gone), or
     the wait's timeout (an hour) has passed, not each time it idles on its own background
     work. `wait` never nudges a conductor. When it returns, go back to 1. Never
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
   - `resume <slug>`: a one-off that an earlier run started. If `swarm.sh status` (this project's
     agents only; `herdr agent list` shows every project's) shows `<slug>` working, `swarm.sh wait
     <slug>` in the background first. Then find its PR
     (`gh pr list --head story/<slug>`, run in the story's repo: the project, or
     `swarm.sh config repos_dir`/`<repo:>` when the story names one) and handle it as for `story`. If there is no
     agent and no PR, the build died: tell the user, and stop.
   - `story <slug>`: a one-off. `swarm.sh story <slug>`, wait for it, and review its PR: every
     check on its head green, `swarm.sh findings <repo> <pr>` triaged, and, before you close the
     builder, `codex exec review` plus `/code-review <PR>` when it changes code (log each fixed
     finding with `SWARM_PROJECT=<project dir> swarm.sh log-finding <kind> <PR URL> "<one line>"`, and
     each declined one with `log-finding --declined <kind> <PR URL> "<the finding, and why>"`), with findings
     sent back through `swarm.sh tell <slug> findings <file>` until a pass on the latest head finds nothing
     substantive
     (method.md § Building).
     Then, if `swarm.sh config merge` is `human` (the default), run
     `swarm.sh review <slug> <PR URL>` and `swarm.sh close <slug>`: the user merges. If it is
     `agent`, merge it, and wait until the PR has merged (a queued merge, auto-merge or a merge
     queue, has not merged yet). Then run `swarm.sh review <slug> <PR URL>` and `swarm.sh reconcile`,
     never a plain `git pull`: reconcile first puts back a retry's `attempts:`, which would stop the
     pull, then pulls the board and finishes the story. Then `swarm.sh unblock` and
     `swarm.sh close <slug>`: closing a story that is still `ready` counts a failed build.

     Give up on the builder as a conductor does when `swarm.sh wait --stall <slug>` returns stalled,
     when it is idle with no PR after wait's nudges, or when review has not converged in the rounds
     you allow: run `swarm.sh close <slug>`, which, on a code, docs or chore story still `ready`,
     counts the attempt and clears its worktree, branch and PR. If the story came back `kind: lead`
     with `escalated_from:`, go back to 1, where `next` names its `escalated <slug>` step. Otherwise
     start it again with `swarm.sh story <slug>`: swarm.sh picks the model, Fable once the story has
     failed `escalate_after` builds (2 by default), so never choose one. With `escalate_after = 0`
     escalation is off: after a story's second failed build, stop and tell the user instead of
     starting it again.

     With `goal` on (`swarm.sh config goal` is not `off`), a bare `swarm.sh close <slug>` on a
     `ready` story is refused, so the give-up closes name their cause: `swarm.sh close <slug>
     stalled` for a stall, and `swarm.sh close <slug> met` when review has not converged. A builder
     idle short of its reply is not nudged and is not given up on as above: read why it stopped and
     close it with that cause, `swarm.sh close <slug> <cause>`. The list below also says whether to
     start it again; the restart above is only for a stall or a review that has not converged.
     Read its reply and its transcript, never its pane. The transcript is
     `<projects>/*/<session>.jsonl`, where `<projects>` is `$CLAUDE_PROJECTS_DIR`, or
     `${CLAUDE_CONFIG_DIR:-~/.claude}/projects`, and `<session>` is field 7 of the last line in
     `.swarm/agents.tsv` whose name (field 3) is the builder's agent name: its slug lowercased, each
     character outside `a-z`, `0-9`, `_` and `-` made `-`, an `s` in front unless it starts with a
     letter, then cut to 32 characters. That line is the current build. The reply comes first (`IMPOSSIBLE:` or the
     story's reply), then the `reason` of the last `goal_status` entry with `met:true`.
     - `met`: the reply is there. Review it as above; the closes after review or merge stay bare.
     - `impossible`: the reply starts `IMPOSSIBLE:`. `swarm.sh close <slug> impossible` makes the
       story `kind: lead`; go back to 1, where `next` names its `escalated <slug>` step.
     - `stalled`: `wait --stall` returned stalled. `swarm.sh close <slug> stalled`, then start it again.
     - `bound`: no reply, and the met entry's reason says the stop-after clause applied.
       `swarm.sh close <slug> bound`, then start it again.
     - `paused`: the goal is still set with no met entry since, and the builder is idle. Send one
       `swarm.sh tell <slug> resume <file>` and wait again; if it stops paused again,
       `swarm.sh close <slug> paused`. That counts nothing, so do not start it again: decide
       yourself what happens to it, as for `cleared-on-error`, and tell the user what you chose.
     - `cleared-on-error`: the transcript holds a `/goal` refusal (a `system` `local_command` entry
       whose stdout refuses `/goal`, with no `goal_status` after it), or the goal is gone and the
       transcript ends on an API error; or `swarm.sh story` failed on a refused goal.
       `swarm.sh close <slug> cleared-on-error`, start nothing more, and decide yourself whether to
       build it again; tell the user what you chose. The story stays `ready` with nothing on it to
       say so, and `next` will name it again: do not start it again until you have decided.
     - None of the above fits (no reply, no refusal, no stall, and no goal entry, or a met entry
       whose reason is not the stop-after clause): `swarm.sh close <slug> stalled`, which counts the
       attempt so `escalate_after` bounds the retries, then start it again.

     If `wait` prints `waiting: dialog open` for an escalate build (`swarm.sh _role <slug>` prints
     `escalate`), it may be Fable's usage-credits consent, and accepting that is yours, not the
     user's. `swarm.sh _target <slug>` prints its pane. Read it with `herdr agent read <pane>`, and
     only if it shows that consent, accept it with `herdr pane send-keys <pane> <key>...`, run
     `swarm.sh dialog <slug> accepted` (or `dismissed` if it would not accept, and tell the user),
     and wait on it again. Never close or tell a builder over a dialog: it is not an attempt. Any
     other dialog, and every permission or tool prompt, is the user's: never send keys to it.
   - `plan-epic <epic>`: follow `/plan-epic <epic>`. When it asks the user to approve the stories,
     that is the user's decision: stop and wait for it. On approval, finish the command and go on.
   - `plan-hld <hld>`: follow `/plan-hld <hld>` the same way; its approval is the user's too.
   - `hld <hld>`: the HLD is a draft, and only the user can write it. Follow `/hld` to resume it
     (the title is in the file): the user works in the co-author's pane, and the review and the
     agreement are picked up in the background. Go back to 1 once `/hld` reports it agreed.
   - `escalated <slug>`: Fable's build of the story failed too, or its builder called it impossible
     (its block starts **Impossible.**): no Fable build failed then, the judge called its **Done
     when** impossible, and that **Done when** is what to re-scope. Deciding what happens to it is
     yours, not the user's, so this is not a stop. Read the story, the block at its end and the attempts'
     PRs it lists, with their review findings. Then decide on the spot, and tell the user in a line
     or two what you chose and why:
     - Re-scope it: change the story so a fresh build can succeed, and run
       `swarm.sh reset <slug> <reason>`. When the board is in the story's repo, a builder reads the
       story in its own worktree, from the branch builds start from, so the new scope has to reach
       that branch first: make the change in a board PR and leave the main checkout's copy alone.
       Once that PR has merged (and, with `pr_per = epic`, once you have merged the base into
       `epic/<epic>` and pushed it), run `swarm.sh reset <slug> <reason> && git pull --ff-only` in
       the board's repo, in one go: `reset` puts the file back to its committed text, so the pull
       brings in the re-scope (its kind, repo, epic and risk included) before anything builds it.
       Until the PR merges, `next` names the story again: that is a wait on the user's merge,
       so name the board PR, show what `swarm.sh status` lists under Waiting on you, and stop.
       A story is reset at most once (`reset` refuses a second, and `next` then says to drop it),
       so after its second failed escalate build, drop it.
     - Drop it: `swarm.sh drop <slug> <reason>` takes it off the board (deleted, or `status: done`
       with `finished = mark`); open a board PR with the change.

     Then go back to 1.
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
is `human` (not `gh pr merge`, not `gh api`, not the web page), and never give a `lead` story
to an agent. Stopping is safe: the next `/swarm-dev:swarm` reads the board and continues.

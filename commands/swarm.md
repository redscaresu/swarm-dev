---
description: Run the whole chain from wherever it stands (HLD, epics, stories, builds), stopping only where the user must decide
---

The board is the directory `swarm.sh config board_dir` prints (`docs/` unless the project's
`.claude/swarm/config` says otherwise); every `docs/hld/`, `docs/epics/` and `docs/stories/` below
is inside it.

Drive the chain end to end, picking up wherever the board says it stands. Requires herdr
(`HERDR_ENV=1`); if not inside herdr, say so and stop. Read `${CLAUDE_PLUGIN_ROOT}/docs/method.md`
first if you have not this session.

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
     for meanwhile must not leave the conductor unwatched. For a conductor it returns only once
     the conductor has written its report or is no longer idle (blocked on a prompt, or gone), not
     each time it idles on its own background work; when it returns, go back to 1. Never
     close a conductor that has not reported.
   - `collect <agent>`: the conductor has finished. Read its report
     (`.swarm/conduct-<epic>.report.md`), relay what merged, what
     is left and what waits on the user, then `swarm.sh close <agent>`.
   - `conduct <epic>`: `swarm.sh conduct <epic>`, then handle it as `wait conduct-<epic>`.
   - `resume <slug>`: a one-off that an earlier run started. If `herdr agent list` shows `<slug>`
     working, `swarm.sh wait <slug>` in the background first. Then find its PR
     (`gh pr list --head story/<slug>`, run in the story's repo: the project, or
     `swarm.sh config repos_dir`/`<repo:>` when the story names one) and handle it as for `story`. If there is no
     agent and no PR, the build died: tell the user, and stop.
   - `story <slug>`: a one-off. `swarm.sh story <slug>`, wait for it, and review its PR: every
     check on its head green, and `swarm.sh findings <repo> <pr>` triaged (method.md § Building).
     Then, if `swarm.sh config merge` is `human` (the default), run
     `swarm.sh review <slug> <PR URL>` and `swarm.sh close <slug>`: the user merges. If it is
     `agent`, merge it; then, if the story is still open on the board, `swarm.sh finish <slug>`;
     then `swarm.sh unblock` and `swarm.sh close <slug>`.
   - `plan-epic <epic>`: follow `/plan-epic <epic>`. When it asks the user to approve the stories,
     that is the user's decision: stop and wait for it. On approval, finish the command and go on.
   - `plan-hld <hld>`: follow `/plan-hld <hld>` the same way; its approval is the user's too.
   - `hld <hld>`: the HLD is a draft, and only the user can write it. Follow `/hld` to resume it
     (the title is in the file): the user works in the co-author's pane, and the review and the
     agreement are picked up in the background. Go back to 1 once `/hld` reports it agreed.
   - `gate`: show the list `next` printed and, for each item, what the user must do (a lead
     story: that you will run it once they say go, and its **You:** steps; a story of any other
     kind: that its `kind` is wrong and must be fixed on the board; a blocked
     story: what blocks it; a later story or epic: set it `ready` or `active` to start it; a PR
     awaiting your merge: merge it, or close it to send the story back to `ready`). Stop.
   - `done`: say so, suggest `/hld <title>` for the next piece of work, and stop.
3. Go back to 1. Every step changes the board (a merge, a new file, a status), so `next` moves on;
   if it prints the same step twice in a row with nothing changed, stop and report why.

Never skip an approval to keep the loop going, never merge red, never merge at all when `merge`
is `human` (not `gh pr merge`, not `gh api`, not the web page), and never give a `lead` story
to an agent. Stopping is safe: the next `/swarm` reads the board and continues.

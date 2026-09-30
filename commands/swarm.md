---
description: Run the whole chain from wherever it stands (HLD, epics, stories, builds), stopping only where the user must decide
---

Drive the chain end to end, picking up wherever the board says it stands. Requires herdr
(`HERDR_ENV=1`); if not inside herdr, say so and stop. Read `${CLAUDE_PLUGIN_ROOT}/docs/method.md`
first if you have not this session.

Repeat until a step below says stop:

1. Run `swarm.sh unblock` (it readies stories whose blockers have merged), then `swarm.sh next`.
   Its first line is the step, the rest is why. Tell the user both in one line.
2. Do the step:
   - `wait <agent>`: a conductor is working. Run `swarm.sh wait <agent>` in the background. It
     returns whenever the conductor goes idle, which it also does while waiting on its own
     background work, so when it returns just go back to 1: `next` says `collect` only once the
     conductor has written its report. Never close a conductor that has not reported.
   - `collect <agent>`: the conductor has finished. Read its report
     (`.swarm/<tab label>.report.md`, where the label is `conduct-<epic>`), relay what merged, what
     is left and what waits on the user, then `swarm.sh close <agent>`.
   - `conduct <epic>`: `swarm.sh conduct <epic>`, then handle it as `wait conduct-<epic>`.
   - `resume <slug>`: a one-off that an earlier run started. If `herdr agent list` shows `<slug>`
     working, `swarm.sh wait <slug>` in the background first. Then find its PR
     (`gh pr list --head story/<slug>`) and review and merge it as for `story`. If there is no
     agent and no PR, the build died: tell the user, and stop.
   - `story <slug>`: a one-off. `swarm.sh story <slug>`, wait for it, review its PR, and merge it
     only when every check on its head is green (method.md § Building); then `swarm.sh unblock`
     and `swarm.sh close <slug>`.
   - `plan-epic <epic>`: follow `/plan-epic <epic>`. When it asks the user to approve the stories,
     that is the user's decision: stop and wait for it. On approval, finish the command and go on.
   - `plan-hld <hld>`: follow `/plan-hld <hld>` the same way; its approval is the user's too.
   - `hld <hld>`: the HLD is a draft, and only the user can write it. Follow `/hld` to resume it
     (the title is in the file): the user works in the co-author's pane, and the review and the
     agreement are picked up in the background. Go back to 1 once `/hld` reports it agreed.
   - `gate`: show the list `next` printed and, for each item, what the user must do (an operator
     story: its **Done when**; a lead story: that you will run it once they approve; a blocked
     story: what blocks it; a later story or epic: set it `ready` or `active` to start it). Stop.
   - `done`: say so, suggest `/hld <title>` for the next piece of work, and stop.
3. Go back to 1. Every step changes the board (a merge, a new file, a status), so `next` moves on;
   if it prints the same step twice in a row with nothing changed, stop and report why.

Never skip an approval to keep the loop going, never merge red, and never give a `lead` or
`operator` story to an agent. Stopping is safe: the next `/swarm` reads the board and continues.

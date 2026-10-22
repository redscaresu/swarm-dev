---
kind: code
status: blocked
depends_on: [board-merge-tells-conductor]
touches: [bin/lib/merge.sh, bin/lib/board.sh:next_report, tests/merge_test.sh, tests/next_test.sh, docs/reference.md:The backlog conductor]
easy: false
estimate_lines: 200
---

# Ready work with no conductor gets one started: after a board merge, and from next

User, 2026-10-22: a board merge's note to the conductor "should also start new agent if necessary and possible". Earlier that day, three no-epic stories were ready while safer-faster-swarm's conductor ran. `next` printed only `wait conduct-safer-faster-swarm`, and the lead had to run `conduct --backlog` by hand.

Needs board-merge-tells-conductor's step in bin/lib/merge.sh that finds the stories a board merge just readied. Add one function that, for each group of ready agent stories (code, docs, chore) with no conductor running, starts one: `conduct <epic>` for an `active` epic whose stories are planned, or `conduct --backlog` for stories with no epic. It starts nothing for an epic that is draft, `split` or awaiting plan approval, nothing while `.swarm/conduct-backlog.report.md` blocks a new backlog conductor (docs/reference.md § The backlog conductor), and nothing when herdr is not available (print what to run instead). Call it after a `merge --board` lands, after the note board-merge-tells-conductor sends. Also call it from `next` before it prints `wait <conductor>`: with ready work no conductor holds, `next` starts that conductor and names it, then prints the wait. A failure to start never fails the merge: warn and exit 0.

**Done when:**
- tests/merge_test.sh: a board merge that readies a no-epic story, with only an epic conductor running, starts `conduct --backlog` (a stub). One that readies a story of an epic with a running conductor starts nothing new and sends the note. One whose epic is draft starts nothing.
- tests/next_test.sh: with an epic conductor running and a ready no-epic story, `next` starts the backlog conductor (a stub) and still prints the epic's wait. With the backlog report present, it starts nothing and says why.
- docs/reference.md says where conductors start on their own.

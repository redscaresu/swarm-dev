---
kind: code
status: blocked
epic: machine-usable
depends_on: [review-pane-closes-after-merge]
needs: [review-pane-closes-after-merge (close_when_idle in bin/lib/lifecycle.sh)]
touches: [bin/lib/lifecycle.sh:close_agent (conductor guard), tests/conductor_close_test.sh (new), commands/swarm.md:collect step, docs/reference-building.md:conductor collect paragraph, bin/lib/merge.sh:board merge tail (Finish PR closes its conductor)]
estimate_lines: 140
easy: false
---

# A conductor's close waits until its Finish PR merged

#690, docs/lead-by-hand.md:19-20: closing a conductor before its Finish PR's `swarm.sh merge --board` exits kills that merge, so leads left finished conductors open. collect already closes the conductor (`swarm.sh close <agent>`, commands/swarm.md:485); it is not auto-closed, because next_step finds a conductor to collect by its live pane (board.sh:346-351). Make that close safe: `swarm.sh close conduct-<epic>` refuses, closing nothing and saying why, while the conductor is working or a Finish PR it opened (`swarm.sh finish <epic>`) is open; an idle conductor with no open Finish PR closes as today. collect's text says to wait for the conductor and close again on that refusal. A gh error reading the Finish PR refuses the close (fail closed). Then close it once the Finish PR merges: `merge --board` of a conductor's Finish PR runs close_when_idle (review-pane-closes-after-merge's detached close) on conduct-<epic>, so the lead need not come back.

**Done when:**
- A new tests/conductor_close_test.sh: closing a working conduct-e closes no pane and prints a line naming it as working; it goes red with the guard removed.
- Closing an idle conduct-e whose Finish PR (gh stub) is OPEN closes nothing and says so; once the stub says MERGED it closes the pane.
- With gh failing to read the Finish PR, the close refuses and says the PR could not be read.
- A merge --board of conduct-e's Finish PR closes conduct-e once it reads idle (fake herdr).
- Closing an idle conduct-e with no Finish PR closes it, as today.
- commands/swarm.md's collect step and docs/reference-building.md's conductor paragraph state the refusal and what to do.

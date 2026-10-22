---
kind: code
status: ready
depends_on: []
touches: [bin/lib/merge.sh, tests/merge_test.sh]
easy: true
estimate_lines: 80
---

# A board merge that readies a story tells that epic's conductor at once

User, 2026-10-22, yes to: "the conductor gets notified immediately when board PRs add ready stories". On 2026-10-22 merge-ins-diff-errors landed ready at 11:47 (#353) and its builder started about 11:55. The conductor was in a review round on #350 and only saw the story on its next pass.

After `swarm.sh merge --board` lands and the board is pulled, find each story that is `ready` now and was not before the merge. For each epic with a running conductor (`conduct-<epic>`), send one `swarm.sh tell conduct-<epic> note` naming the new ready stories and asking it to start them now, within its builder limits. A story with no epic goes to the backlog conductor when one runs. With no conductor running, send nothing, and print one line saying `next` will start it. The tell must never fail the merge: if it fails, print a warning and exit 0.

**Done when:**
- tests/merge_test.sh: a board merge that turns two stories of epic e ready, with conduct-e running (a stub herdr/tell), sends one note naming both. One that readies nothing sends none. One whose tell fails still exits 0 and warns.
- The story's PR shows the note text the conductor receives.

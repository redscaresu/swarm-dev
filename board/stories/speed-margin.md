---
kind: lead
status: ready
epic: port-checks
depends_on: []
touches: [board/stories/speed-run.md:margin line]
estimate_lines: 0
easy: true
---

# You set the margin that counts as slower for the speed job

**You:** give the margin by which a command's median wall time on CI may exceed its baseline tree's before the speed job fails. That is a percentage and, if you want one, a floor in milliseconds below which no difference fails. The lead suggests 20% with a 100 ms floor, as CI runners vary from run to run. Process starts are reported and never fail the job. The lead writes your answer into speed-run's story file before that story goes ready. No PR.

**Done when:**
- speed-run's story file states the margin you gave, in your words, with the date.

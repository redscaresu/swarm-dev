---
kind: lead
status: blocked
epic: merge-mechanics
after: merge-mechanics
depends_on: [release-upgrade-confirm]
needs: [release-upgrade-confirm (the question in commands/swarm.md's release arm and the --upgrade flag on merge --release.)]
touches: []
estimate_lines: 0
easy: true
---

# Lead: Answer merge --release's upgrade question when cutting v0.31.0

Needs from release-upgrade-confirm: the release arm's question and merge --release --upgrade. The epic's Your part step 3. after: merge-mechanics. The cut itself is board/stories/release-v0-31-0.md, which board-loose-ends touches, so this step is a story of its own.
**You:** when the lead asks whether to move the running agents onto v0.31.0, answer yes or no.
The lead then checks that merge --release printed the upgrade's log lines (yes) or the `upgrade not run:` line (no), and records the answer and that line here.

**Done when:**
- This story records the user's answer and the line merge --release printed for it.

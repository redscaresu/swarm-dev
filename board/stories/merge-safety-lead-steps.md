---
kind: lead
status: blocked
epic: merge-safety
depends_on: [dropped-lines-hold, dropped-hold-shown]
needs: [dropped-lines-hold (the holds this story reconciles), dropped-hold-shown (where they show)]
touches: []
estimate_lines: 0
easy: false
---

# Lead: the plan PR's stage read (met), and dropped-lines holds the builder answered

From dropped-hold-shown it uses the `(dropped base lines)` row in status and the held merge: line, whose exit this step acts on. The epic's Your part. 1. Already met, nothing left: the HLD's plan PR #719 merged on 2026-10-29 at 02:53Z with every v0.30.0 epic active and every v0.31.0 epic draft. Its body says so, and origin/main at 62c13b35 has 7 active v0.30.0 epics and 10 draft v0.31.0 epics. 2. **You:** from the time dropped-lines-hold merges until the v0.30.0 cut, wait --lead or status may show a PR held for dropped base lines whose builder answered in the PR instead of restoring the lines. Read the answer. If the drop is meant, merge the PR by hand. If not, tell the lead, who sends the builder a nudge to restore the lines in a commit of its own. 3. **You:** a hold whose check could not run (`dropped base lines unchecked:`) is yours the same way: run `git show --remerge-diff <merge>` on the PR's merge commits, as docs/lead-by-hand.md's #693 entry did, then merge by hand or have the lines restored. At the release, the lead reconciles every dropped-lines hold recorded since dropped-lines-hold merged with its PR's outcome and the user's decision (status and events.tsv), rather than reading an empty status row as proof. The remerge-diff fallback command lives in this story, since dropped-lines-hold deletes lead-by-hand's #693 entry.

**Done when:**
- At the v0.30.0 cut, `swarm.sh status` lists no `(dropped base lines)` row.
- Each PR held that way since dropped-lines-hold merged was either merged by hand after its answer was read, or had its lines restored by its builder. The lead lists them, or says none, in the release-v0-30-0 PR.

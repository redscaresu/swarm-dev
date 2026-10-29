---
kind: lead
status: ready
epic: lead-woken
depends_on: []
touches: [board/stories/release-v0-30-0.md, board/stories/no-review-restart.md, board/hld/2026-10-28-swarm-dev-0-30-and-0-31.md:Open questions]
estimate_lines: 0
easy: false
---

# Lead: the release-v0-30-0 edits, N for stuck:, and the no-review-restart dependency

The epic's Your part, plus one dependency this plan needs. 1. Lead, now, by board-pr (a plan PR cannot touch stories, commands/plan-hld.md:156-168): edit board/stories/release-v0-30-0.md as the epic's Your part lists. That means a second baseline, a self-closing Done when, step 5's two-step activation of v0.31.0, and the #696 lead-by-hand removal in its docs step. 2. **You:** confirm N for the stuck: line (HLD Open question 4). This plan proposes 60 minutes (stuck-builder-line's STUCK_MINUTES). That is half of #641's 2 h, well under #633's 3.5 h, and twice stall_minutes (30). A selected test run and a live background task are ruled out by their own checks, not by N. Reply yes, or give another N. The lead learns it is done from your reply, then edits stuck-builder-line's scope before it starts if N changed, and strikes Open question 4 in the HLD with N and the date. 3. Lead, in the same board PR as step 1: add lead-alerts-wired to delivery-liveness's no-review-restart depends_on, because both edit docs/reference.md's wait --lead command row and AGENTS.md's wait --lead bullet. Or drop those two parts from no-review-restart, since lead-alerts-wired makes both point at § The lead. The N question (stuck-builder-line's 60-minute default) is asked at the release-v0-30-0 cut, not before the build: the default ships overridable, so nothing waits on the answer.

**Done when:**
- board/stories/release-v0-30-0.md on main has the four edits step 1 lists.
- no-review-restart.md's depends_on names lead-alerts-wired, or its touches no longer name the wait --lead row and the AGENTS.md bullet.
- The HLD's Open question 4 is struck with the confirmed N and its date.

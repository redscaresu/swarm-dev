---
kind: lead
status: blocked
depends_on: [close-exact-tab, conductor-lanes, conductor-lanes-start, findings-told-sent, grant-pinned-head, grant-protected-paths, hld-docs-method-reference, hld-docs-readme-agents, ladder-top-rung-to-lead, release-base-pin, review-loop-knobs, step-up-slow-start, tell-false-not-taken-up, test-run-log]
touches: [board/stories]
estimate_lines: 0
easy: false
---

# The 0.27 retro, held with the user before the release

Every release starts with a retro (user, 2026-10-23). The lead brings the list below, plus the conductors' `declined out-of-scope` findings since v0.26.0 (`awk` over .swarm/findings.tsv by date) and flow's holds, review_loops and test_runs figures. Each item either becomes a story or is dropped with a reason. Rules that live only in the lead's memory move into swarm-dev.

**Incidents and flow, 2026-10-24**
- False "not taken up" on tell, step-up, conductor starts and the fallback reviewer (the fixes are tell-false-not-taken-up and step-up-slow-start). One case was real: a brief sat unsent in the input box for hours, and status read the builder as idle.
- Whole-file `touches` caused at least four false clash holds (#439, #447, #466). Should /plan-epic write touches as file:part, or should the clash check compare only parts?
- A 50-minute hold went unrecorded (fixed by hold-event and flow-holds).
- Review loops ran to rounds 7 to 9. The ladder was off for days, held behind a stale story, and was blind to misreported tells.
- Test contention: up to 8 full suites at once, load 45 to 83 on 10 CPUs, suites taking 40 to 55 minutes. The user chose to track it (test-run-log), not cap it. Decide from the test_runs data.
- One backlog conductor worked through 7 green PRs one at a time (fixed by conductor lanes).
- Codex usage limit, with the sonnet fallback failing to start.

**Follow-ups from conductor reports (scratchpad conduct-*.report.md)**
- epic-guard:
  - an epic added as later can be flipped to active with no ticket;
  - a plain story merge that flips an epic to active is unguarded;
  - any new `agreed:` date is accepted, and a rename launders a stale one;
  - `parent:` is read only at the base;
  - renaming an active epic is refused;
  - the contents reader is copied three times (merge_read, pr_hld, release_check);
  - pr_hld treats any 404 as deleted;
  - `next` still reports every draft epic as "run /epic";
  - commands/swarm.md reads lead_epics from the file.
- plan-hld:
  - dash does not match plan or finish PR rows;
  - `plan_head` accepts an unchanged `planned:`;
  - #441 edited outside its touches;
  - HLD names with `.` or `_` pass next but are refused elsewhere;
  - HLDs decomposed before `planned:` existed are offered plan-hld again and need `planned:` set by hand (an upgrade note);
  - /plan-hld reruns the whole swarm when an empty worktree is gone;
  - an HLD with no `## Epics` makes the PR fall to none silently;
  - a closed plan PR leaves critic.json behind;
  - an off-repo board leaves the HLD stuck when a run is interrupted;
  - the plan-hld step reads the main checkout's grants.
- hld-grants: dash-grant-queue (later).
- review_test broken-pipe flake; herdr "start was unclear"; a builder's `rm -rf` permission prompt.
- Older: the lead_queue keep rule; false stalls from `wait --stall`; the loose-match lint missing `=~`; epic.md and hld.md step 5 lacking a board-pr worktree; dash_finished BOARD_OWN missing hld/; init never updating Board.base.

**Lead-only practice to move into swarm-dev**
- The handover bundle for moving machines (~/swarm-handover: .swarm without sessions, the lead's memory, uncommitted board edits).
- The usage watch: a heads-up at 90% of weekly usage, read from the session logs.

**You:** go through the list with the lead and decide each item.

**Done when:**
- Every item above is a filed story or is dropped with a reason, recorded in this file, and the user has seen it.

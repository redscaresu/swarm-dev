---
kind: lead
status: later
depends_on: []
touches: []
---

# Lead: cut v0.30.0, and switch on the next stage

The 0.28 HLD ships in staged releases (board/hld/2026-10-25-swarm-dev-0-28.md, Rollout § Stages). The plan PR could only add epics, so each stage's release is this lead story (stage-gating's constraints). Start it when `swarm.sh next` prints `release v0.30.0`.

1. **Docs.** List the behaviour changes since v0.29.0 (`git log v0.29.0..origin/main`). Each story updated its own docs; check README.md, AGENTS.md, docs/ and commands/ cover every change, and land a docs PR for any gap. In the same docs PR, delete docs/lead-by-hand.md's entries this release fixes, #696's among them (rules-file shipped its two rules), with each fixed entry's issue closed, as the 1c rules for that file say.
1b. **The skill.** Bring skills/swarm-dev/SKILL.md up to v0.30.0: every command, `wait --lead` line and step it names must match what v0.30.0 does. Land it in the docs PR (the user asked for this on 2026-10-30; it had fallen behind).
1c. **The lead's stopgaps.** For each script the lead wrote to work around a swarm-dev gap (in .swarm/: can-run-now.py, conflict-teller.sh, lead-check.sh, lead-loop.sh, lead-watchdog.sh, plan-pipeline.sh, plan-summary.py, plan-waiter.sh, pr-green.sh, review-manager.sh, untriaged.py, write-stories.py; and /tmp/plan-epic.sh), check whether v0.30.0 does its job. Delete each one it does. List the ones kept, each with the gap it still covers, in the release PR body (the user asked for this on 2026-10-30).
2. **Read the review loop's number.** The v0.30.0 build ran on the 0.29.x plugin, so this reading is a second baseline beside v0.29.0's, not a reading of the new loop (the 0.30 HLD, Rollout § Readings): record it as that. Run `swarm.sh flow --since <v0.29.0 tag date> --until <today>`. In `time_in_state`, read the `all` row's `green_to_review_p90`. M is that row's `prs`. N is how many of those PRs have a `green_to_review_min` value in `swarm.sh outcomes --since <v0.29.0 tag date>`, each PR counted once. Record "<p90> min over N of M PRs", against the 10-minute bar, in the release PR body and in `board/retros/v0.30.0.md`. With an empty p90, record "none: no review round started after green in the window".
3. **The release PR**, through /swarm-dev:swarm's release arm: bump only `.claude-plugin/plugin.json` to 0.30.0, list the PRs merged since v0.29.0, the behaviour changes every project gets on upgrade, and the infrafactory build they were tried on (or none). No HLD grants `release`, so the user merges it.
4. **You:** merge the release PR, then restart the lead session (`/exit`, then `claude --continue`) so it runs v0.30.0. The lead learns it is done when `swarm.sh version` prints 0.30.0.
5. **The next stage, in two steps.** Once v0.30.0 is tagged, `next` prints `stage v0.31.0`. (a) Its board PR sets the v0.31.0 draft epics active: flaky-tests, board-loose-ends, machine-usable, merge-mechanics and deferred-700 (reference-split already shipped in v0.30.0, moved there on 2026-10-29). (b) Once those five are planned, a second board PR sets the 0.28 HLD's retro-gate, retro-report and handover-usage active, so the retro gate goes last (0.30 HLD, Rollout § Stages).
6. **Before the cut, ask the user** to confirm stuck-builder-line's N (60 minutes by default, SWARM_STUCK_MINUTES) and ladder-cost's threshold decision (ladder-threshold-decision), and record both answers in the release PR body.


**Done when:**
- The tag v0.30.0 exists, `gh release view v0.30.0` shows it, and `swarm.sh version` in the lead session prints 0.30.0.
- The `all` row's `green_to_review_p90`, as "<p90> min over N of M PRs" (or "none: no review round started after green in the window"), against the 10-minute bar, is in the release PR body and in `board/retros/v0.30.0.md`.
- The v0.31.0 stage's epics are active on main, in step 5's two steps.
- skills/swarm-dev/SKILL.md on main names no command or line that v0.30.0 lacks, and its version notes reach v0.30.0.
- Every stopgap listed in step 1c is either deleted or named in the release PR body with the gap it still covers.
- This story's file leaves the board: `swarm.sh finish release-v0-30-0` once every item above holds.

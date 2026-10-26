---
kind: lead
status: later
depends_on: []
touches: []
---

# Lead: cut v0.30.0, and switch on the next stage

The 0.28 HLD ships in staged releases (board/hld/2026-10-25-swarm-dev-0-28.md, Rollout § Stages). The plan PR could only add epics, so each stage's release is this lead story (stage-gating's constraints). Start it when `swarm.sh next` prints `release v0.30.0`.

1. **Docs.** List the behaviour changes since v0.29.0 (`git log v0.29.0..origin/main`). Each story updated its own docs; check README.md, AGENTS.md, docs/ and commands/ cover every change, and land a docs PR for any gap.
2. **Read the review loop's number.** Run `swarm.sh flow --since <v0.29.0 tag date> --until <today>`. In `time_in_state`, read the `review-loop` row's `green_to_review_p90`. Run `swarm.sh outcomes --since <v0.29.0 tag date>` and count the PRs with a value in its `green_to_review_min` column; that is the PR count (the row's `prs` counts every merged PR). Record both, against the 10-minute bar, in the release PR body and in `board/retros/v0.30.0.md`. With no value, record "none: no review round started after green in the window".
3. **The release PR**, through /swarm-dev:swarm's release arm: bump only `.claude-plugin/plugin.json` to 0.30.0, list the PRs merged since v0.29.0, the behaviour changes every project gets on upgrade, and the infrafactory build they were tried on (or none). No HLD grants `release`, so the user merges it.
4. **You:** merge the release PR, then restart the lead session (`/exit`, then `claude --continue`) so it runs v0.30.0. The lead learns it is done when `swarm.sh version` prints 0.30.0.
5. **The next stage.** Once v0.30.0 is tagged, `next` prints `stage v0.31.0`: follow its arm to set that stage's draft epics active (a board PR under the HLD's `epics` grant).


**Done when:**
- The tag v0.30.0 exists, `gh release view v0.30.0` shows it, and `swarm.sh version` in the lead session prints 0.30.0.
- The `review-loop` `green_to_review_p90` and the count of PRs with a `green_to_review_min` value (or "none: no review round started after green in the window"), against the 10-minute bar, are in the release PR body and in `board/retros/v0.30.0.md`.
- The v0.31.0 stage's epics are active on main.

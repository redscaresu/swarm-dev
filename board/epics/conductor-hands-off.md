---
status: active
hld: 2026-10-25-swarm-dev-0-28
stage: v0.29.0
depends_on: [review-loop]
---

# The conductor stays one per epic and stops carrying PRs

The conductor stays one per epic and stops carrying PRs: it starts a review agent once per PR when the PR opens, starts builds as stories go ready, takes escalations, and ends the epic when the last PR merges with no tab left open; upgrade waits for whichever agent owns a PR; the lanes-review items that apply on main become tests; lanes, their PRs, branches and stories are dropped; flow gains the per-PR green-to-review column. HLD Goal 5, Design § Review in parallel (the conductor, lanes, the checklist).

**Done when:**
- The conductor brief's review_rule, conduct_merge_rule and stop_rule (bin/lib/build.sh:44-60) say: start review-<slug> once when a story's PR opens (watch returns on a new PR), never wait on a PR, never triage or merge; the conductor's report (build.sh:961-967) is not written while a review agent owns an open PR, and the epic is finished when the last PR merges; next_step treats the report as the finish sign as today (board.sh:212); a test for the report hold and one for the finish.
- swarm.sh upgrade waits for whichever agent owns a PR, not only the conductor (lifecycle.sh:2433-2462; upgrade_want already lists review agents by name); tests/upgrade_test.sh.
- Lanes-review items that apply on main, each a test that fails before and passes after: notes queued during reconcile survive a reconcile that fails under set -e (tell_note path, agents.sh; board.sh reconcile); flow's idle_slots and dash's reported conductors key agents by exact name and never guess a report name (bin/lib/flow_idle_slots.py, bin/lib/dash_finished.py; uses less-noise's name-cut helper); a story blocked on a kind: lead parent or a blocked parent with no depends_on is not reported as waiting on an agent in the conductor's stop_rule, status or next. Dropped with the reason 'lanes-only, nothing on main': the start reservation release (grep reserv in bin/lib finds only reserved_env) and the lane fold's single source.
- flow's time_in_state gains a per-PR `green_to_review_min` column (minutes from the green check on a head to the first review round's start, from events.tsv and the PR's check runs already read by outcomes_join.py:65) with a fixture test; reference.md documents it.
- Lead story, with the user's go: #480 and #482 closed, branches story/conductor-lanes and story/conductor-lanes-start deleted, the three lanes story files removed by a board PR (conductor-lanes-on's depends_on release-027 names nothing on the board).
- AGENTS.md, README.md and docs/reference.md describe the conductor's new scope; doc_check passes.

**Out of scope:**
The review agent's loop and merge (review-loop); lanes; changing one conductor per epic; the measurement reading (v0.30.0 release story and the retro).

**Constraints:**
- Depends on review-loop at epic level: the conductor stops carrying PRs only once a review agent can merge, so the brief changes land in order and each merge to main keeps make test green.
- The exact-name metrics story names less-noise's name-cut helper story in depends_on (cross-epic clash on lifecycle.sh name sites).
- Closing PRs and deleting branches are outward-facing: a kind: lead story with the user's go, never an agent's.
- tests/upgrade_test.sh, tests/tell_note_test.sh, tests/flow_idle_slots_test.sh (or the flow test that covers it), tests/dash_test.sh pin today's paths.
- bash 3.2, shellcheck, loose_match_test, lib_path_test, make test; humanizer over AGENTS.md, README, docs prose.
- Order: less-noise's nudge story goes after this epic's conduct_brief story (both edit green_rule and the nudge sites, bin/lib/build.sh:971-980, 977, 1101, 1127; review-loop's Done when 2 moves green_rule's job first, which this epic depends on).

**Areas:** bin/lib/build.sh:conduct_brief rules, bin/lib/build.sh:conductor report, bin/lib/lifecycle.sh:upgrade, bin/lib/board.sh:reconcile notes, bin/lib/agents.sh:tell_note, bin/lib/flow_idle_slots.py, bin/lib/dash_finished.py, bin/lib/flow_time_in_state.py, bin/lib/outcomes_join.py:review_wait, board/stories (three lanes files removed), AGENTS.md:conductor lines, docs/reference.md:conductor and time_in_state, README.md, tests/

**Your part:**
User: go before the lead closes #480 and #482 and deletes their branches. Lead: that story. Nothing else; the cut is the release story's.

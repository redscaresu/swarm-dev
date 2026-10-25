---
status: draft
hld: 2026-10-25-swarm-dev-0-28
stage: v0.29.0
depends_on: [stage-gating, test-speed, clash-by-part, no-agent-alert, liveness-signals]
---

# The review agent owns its PR from green CI to merge or to the user

The review agent owns its PR from green CI to merge or to the user: it waits for green, triages its findings, tells its builder (which fires the ladder), waits for the new head, runs round 2 and later with codex only, handles a red head and scanner findings, and on a pass merges through swarm.sh merge under merge = agent or a merge grant, or hands the PR to the user. HLD Goal 5, Design § Review in parallel (the agent, its gates, its tell, the landing queue). risk: high.

**Done when:**
- merge_caller (bin/lib/merge.sh:92-116) accepts a `review-` pane under merge = agent and, under merge = human, a `review-` pane whose PR's HLD grants merge (merge_grant, merge.sh:118-133, runs for that caller), and still refuses a builder's pane and a `review-` pane with no grant under merge = human; tests/merge_test.sh covers the five cases; the review brief carries the project root (the agent runs in the story's worktree, build.sh:599-600).
- The review brief (bin/lib/build.sh:749-794) gains: wait for green with swarm.sh wait-pr; triage of `swarm.sh findings` scanner notes and code-scanning alerts before the PR counts green (today the conductor's green_rule, build.sh:983-990); fix-or-decline of its own findings logged with log-finding --round; `swarm.sh tell <slug> findings`; a red head after a fix push told to the builder as ci-red, counted as today's ci-red-2 trigger; the pass rule (a round with nothing fixed is a pass); then swarm.sh merge or swarm.sh review <slug> <url>. It loses 'You are read-only' (build.sh:760); AGENTS.md:75, docs/reference.md:730 and 2002, bin/swarm.sh:48, bin/lib/build.sh:56 and dash's text match; codex and the fallback reviewer stay read-only; doc_check passes.
- Round 2 and later: the plan picks one mechanism, the agent looping in its session or a restart per round, and tests it: the round number is right (today fixed into the brief at start, build.sh:597, 614-617), round 2 runs codex and skips /code-review, .head is refreshed (build.sh:619), and review_agent's refusal while review-<slug> is live (build.sh:588-590) does not block the chosen mechanism; tests/review_agent_test.sh (SERIAL) pins it.
- A review agent's tell counts the round and steps the builder up at step_up_findings or holds at top_rung_rounds (bin/lib/agents.sh:1619-1632, 1679) with a review pane as caller; the step-up path's shut_agent (lifecycle.sh:629-631) does not close the calling review agent's own tab; a failed step-up leaves its marker (no-agent-alert's lead line) and a note in the conductor's inbox; a test per case.
- A merge run from the review pane survives its own reconcile: reconcile's close of the builder (board.sh:1488) and close_panes' fallback to close_tabs on the slug (lifecycle.sh:1239-1250) never close the pane that is merging, including a backlog story's review agent in the story's own tab and the close_agent path less-noise's reconcile adds for a story whose file the pull removed (board.sh:1564-1575); after the merge the conductor's finish, or tidy, closes review-<slug>, and a test shows no tab left open for the story.
- no-agent-alert's tests pass with the review agent as PR owner, and a review agent gone with an open PR and no round under way reaches wait --lead (the true case under the new owner); a test per case.
- docs/features.tsv has the row for review agents owning the loop with metric `flow time_in_state: green_to_review_min per PR, p90` (the column is conductor-hands-off's), bar 10 min, and the 2026-10-24 baseline (seven green PRs carried one at a time); the reading is taken at the v0.30.0 release story and the retro.

**Out of scope:**
The conductor's side (conductor-hands-off); several conductors per epic (lanes); a separate closer role; a tool deny list enforcing 'never edits code' for the review role (only review-fallback has one, bin/lib/agents.sh:506-519: it stays brief text unless a story adds it cheaply); changing the guard hook; live measurement inside this stage.

**Constraints:**
- Every merge still goes through swarm.sh merge: head pinned, every check green, reconcile lock (bin/lib/board.sh:1542-1557); costs: money still holds for any caller (merge.sh:256).
- The merge guard (hooks/merge-guard.sh) does not change; it checks command text, not role, so merge_caller is the only gate on a review pane.
- tell dies on a busy target (agents.sh:1612); the review agent waits with swarm.sh wait or wait-pr, never a hand-written loop.
- A review agent's name is review-<slug> cut to 32 chars (bin/swarm.sh:425-431); match on exact records.
- This epic owns bin/lib/build.sh's review_brief and review_checklist; conductor-hands-off owns conduct_brief's rules and less-noise's brief-form story names this epic's brief story in depends_on.
- tests/review_agent_test.sh (SERIAL), tests/merge_test.sh (SLOW), tests/escalate_*_test.sh, tests/ladder_top_rung_test.sh, tests/tell_note_test.sh pin today's paths.
- risk: high on the merge_caller and brief stories; touch docs/features.tsv as `docs/features.tsv:review-owner row`; bash 3.2, shellcheck, make test; humanizer over AGENTS.md, README, docs prose.
- Order: merge-holds' pinned-head story goes after this epic's merge_caller/merge_grant story (both edit bin/lib/merge.sh:merge_grant, merge.sh:122).
- Order: this epic's self-close story goes after less-noise's name-cut story (lifecycle.sh:1241-1246 is inside close_panes, :1231-1257) and after less-noise's reconcile story (the close_agent path at board.sh:1564-1575), and tests that path.
- Order: less-noise's AGENTS.md stories go after this epic's AGENTS.md review-agent line story (shared hot file, commands/plan-epic.md:69).

**Areas:** bin/lib/build.sh:review_brief, bin/lib/build.sh:review_checklist, bin/lib/build.sh:review_agent and review_round, bin/lib/merge.sh:merge_caller and merge_grant, bin/lib/agents.sh:tell_agent, bin/lib/lifecycle.sh:shut_agent and close_panes, bin/swarm.sh:usage header, AGENTS.md:review agent line, docs/reference.md:review agent, docs/method.md, docs/features.tsv:review-owner row, tests/ (review_agent, merge, escalate_*, tell_note, wait_lead)

**Your part:**
None; the cut is the release story's (stage-gating's constraints).

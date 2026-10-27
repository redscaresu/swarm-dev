---
kind: code
status: blocked
epic: stuck-work
depends_on: [stuck-work-watch]
needs: [stuck-work-watch: lead_queue, the wait --lead handler, KINDS and the wait --lead and method.md lines as it leaves them (shared parts)]
touches: [bin/lib/lifecycle.sh:lead_queue, bin/lib/lifecycle.sh:open_story_prs (new), commands/swarm.md:wait --lead handler, tests/lead_handler_test.sh:KINDS, tests/unmerged_conflict_test.sh (new), docs/reference.md:wait --lead lines, docs/method.md:Every stop names its exit]
estimate_lines: 220
easy: false
---

# wait --lead names a reviewed PR left unmerged, and a PR that conflicts with its base

Uses stuck-work-watch's lead_queue, handler arms, KINDS and docs lines as it leaves them (shared parts). From stuck-work-watch's old text: `unmerged: <slug> <PR>, exit: swarm.sh merge <PR>` for a PR that passed review on its current head, is green and mergeable, and has been open past queue_minutes (#508 sat 1h45 and #539 over an hour in v0.28.0); `conflict: <slug> <PR>, exit: tell its builder to merge the base in` for an open story PR CONFLICTING with its base. lead_heads reads only the items waiting on a human merge (lead_review_items, bin/lib/lifecycle.sh:2066-2090), so add open_story_prs (lifecycle.sh, new): every open story PR in both merge modes and every build state (builder working, in review, kept, no build), with one gh pr list per repo per poll carrying head, mergeable and checks; say in the PR how many gh calls a poll adds. main red stays fix-main's. Each wakes the lead once per occurrence; KINDS gets unmerged and conflict; docs/method.md's 'Every stop names its exit' names them. merge-holds' protected-hold-queue also edits lead_queue: story --strict serialises the two.

**Done when:**
- tests/unmerged_conflict_test.sh (new), under merge = agent and merge = human, with the PR's story building, in review, kept and with no build: each line fires on its real case, and stays silent on a PR reviewed on an older head, one mergeable but not reviewed, one open under queue_minutes, and one MERGEABLE. Each check fails with its line removed or its read narrowed to lead_heads' items.
- tests/lead_handler_test.sh passes with unmerged and conflict in KINDS.

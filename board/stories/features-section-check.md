---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [flow-tell-refusals, flow-start-failures, flow-incidents-causes, lead-queue-p90, merge-holds-by-kind, pr-lifecycle-events, review-event-fields]
needs: [flow-tell-refusals: bin/lib/flow_tell_refusals.py, flow-start-failures: bin/lib/flow_start_failures.py, flow-incidents-causes: flow incidents' cause and stalled-input tables, lead-queue-p90: flow lead_queue's p90_min, merge-holds-by-kind: flow merges' dropped_lines column]
touches: [tests/features_test.sh:section and column check, docs/features.tsv:Goal 2 to 8 rows, docs/features.tsv:Goal 6 rows (new), docs/reference-logs.md:goal-to-section table (new, Flow and features)]
estimate_lines: 160
easy: false
---

# features_test checks each flow metric names a section and column that exist; goal-to-section table

From flow-tell-refusals and flow-start-failures it uses their new flow_<section>.py files (features.tsv:64, :66 name them); from flow-incidents-causes, lead-queue-p90 and merge-holds-by-kind, the columns they print (rows 65, 63, 67). tests/features_test.sh gains a check over docs/features.tsv: a metric naming `flow <section>` (not `flow:` with no section, not a metric without flow) names a bin/lib/flow_<section>.py that exists; for a row whose landed names an epic of board/hld/2026-10-28-swarm-dev-0-30-and-0-31.md, the column after the colon is a header word that section prints over a fixture giving it a row. Re-spell rows 62-67 (Goals 2, 3, 4, 5, 8) to pass it, bars kept; add Goal 6's rows with event: uses of pr-opened, first-green and review-finished. The only story that edits docs/features.tsv. docs/reference-logs.md's Flow and features gains the goal-to-section table for Goals 1 to 5.

Lead decisions (2026-10-30): the check is one section per bar, not per goal (Goal 1 and Goal 5 have two bars each). Row 62 (lead-hand per 100 merged story PRs) and row 68 (reference split) are exempt by name with the reason in the test, since their reading joins two sections or reads files rather than a flow column; the release-v0-30-0 PR records those two readings by hand. The epic's 'flow test_runs resolves a run's slug' is already true (flow_test_runs.py reads the branch), so no story changes it.

**Done when:**
- tests/features_test.sh: a fixture row naming `flow no_such_section` fails the check; one naming `flow lead_queue: no_such_column`, landed an epic of the HLD, fails it; `flow:` and a metric without flow pass.
- docs/features.tsv passes the check, rows 62-67 in `flow <section>: <column>` spelling, with Goal 6's rows present.
- Copy-aside proof: in a worktree copy, deleting bin/lib/flow_start_failures.py turns the real-file check red.
- docs/reference-logs.md has the goal-to-section table; tests/doc_check_test.sh passes.
- The exemption list names exactly rows 62 and 68, each with its reason; removing either name turns the check red.

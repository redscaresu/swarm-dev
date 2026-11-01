---
kind: code
status: blocked
epic: machine-usable
depends_on: [flow-panes, flow-test-runs-timeouts, review-pane-closes-after-handover, conductor-pane-closes, planning-panes-close, mutation-proof-on-copy, builder-pushes-once]
needs: [flow-panes (the `flow panes` section and its over_30 column (features_test checks the row names a printed column).), flow-test-runs-timeouts (the `timeouts` column of `flow test_runs`.), review-pane-closes-after-handover (and through it review-pane-closes-after-merge), conductor-pane-closes, planning-panes-close (#690 fixed before its entry goes.), mutation-proof-on-copy, builder-pushes-once (#695 fixed before its entry goes.)]
touches: [docs/features.tsv:Goal 11 rows, docs/lead-by-hand.md:Finished panes left open, docs/lead-by-hand.md:builder that keeps changing its PR, tests/features_test.sh:section fixture (test-runs.tsv, pane-closed lines)]
estimate_lines: 20
easy: true
---

# Goal 11 rows in features.tsv; drop #690 and #695 from lead-by-hand

Uses the two flow columns and the fixes above. docs/features.tsv gains two rows, landed machine-usable: review panes open 30 minutes after their merge or handover (`flow panes: over_30`, baseline: 25 review panes left open for hours, HLD:91-92, bar 0); test-file timeouts per release build (`flow test_runs: timeouts`, baseline 2,050 in the v0.30.0 build, bar under 100). docs/lead-by-hand.md loses 'Finished panes left open' (#690, :16-22) and 'A builder that keeps changing its PR' (#695, :31-38); other entries stay (open PR #812, merge-mechanics and flaky-tests edit others). tests/features_test.sh runs each row's flow section over a fixture with no test-runs.tsv and no pane-closed lines (:146-156), so add those to its fixture: valid run rows in test-runs.tsv, and reap and pane-closed lines in events.tsv (scripts/test.sh:187 writes reaps there).

**Done when:**
- tests/features_test.sh passes with both rows; it fails if either row's column is renamed.
- docs/lead-by-hand.md no longer has the #690 or #695 entry, and every other entry is unchanged.
- The PR says humanizer ran over the changed prose.

---
status: active
agreed: 2026-11-24
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
parent: helpers-shared
depends_on: [foundation-exit, helpers-shared-base]
---

# events_outcome and touches_rows run as Go, and resend_pass calls the binary

events_outcome and touches_rows exist as Go beside their Python copies. The outcome scan check moves to Go, and resend_pass's inline site calls the binary.

A child of [helpers-shared](helpers-shared.md), split on 2026-11-23. The parent's constraints and its shared rules (L2, the P rules) apply here unchanged.

**Done when:** internal/eventsoutcome and internal/touchesrows each have a comparison test that runs the Python and the Go over the same fixtures, the malformed cases among them, compares the output byte for byte, and fails when either side alone is changed. The outcome-scan check from docs/port/tests.tsv runs in Go and keeps the assertion its go_check column names. bin/lib/lifecycle.sh's resend_pass runs `_resend-rows`, and the differential run is clean for its fixtures.

**Stories:**
- [go-events-outcome](../stories/go-events-outcome.md)
- [outcome-scan-go](../stories/outcome-scan-go.md)
- [go-touches-text](../stories/go-touches-text.md)
- [go-touches-files](../stories/go-touches-files.md)
- [go-resend-rows](../stories/go-resend-rows.md)
- [resend-pass-binary](../stories/resend-pass-binary.md)

**Out of scope:**
- Porting any importer of events_outcome or touches_rows

**Your part:**
- None beyond the parent's: L2 patches.

**Areas:**
- go-events-outcome: [internal/eventsoutcome/eventsoutcome.go, internal/eventsoutcome/compare_test.go]
- outcome-scan-go: [internal/eventsoutcome/scan_test.go, internal/eventsoutcome/testdata/scan]
- go-touches-text: [internal/touchesrows/text.go, internal/touchesrows/text_compare_test.go]
- go-touches-files: [internal/touchesrows/files.go, internal/touchesrows/files_compare_test.go]
- go-resend-rows: [internal/resend/rows.go, internal/resend/rows_test.go, cmd/swarm/resend_rows.go, bin/ported/_resend-rows]
- resend-pass-binary: [bin/lib/lifecycle.sh:resend_pass, docs/port/sites.tsv:resend_pass row, docs/port/copies.tsv:resend_pass row, docs/port/swarm-names.tsv:SWARM_PANES row, docs/port/swarm-names.tsv:SWARM_BACKLOG row, docs/port/swarm-names.tsv:SWARM_NAME_MAX row, docs/port/swarm-names.tsv:SWARM_BRIEFS row, tests/diff_fixtures_resend.sh, tests/events_tail_lead_test.sh:tell_resend, tests/lead_queue_wait_test.sh:resend_pass checks, tests/speed_list.txt:resend_delivery line]

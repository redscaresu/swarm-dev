---
kind: code
status: later
epic: helpers-shared
depends_on: [go-report-gh, go-flow-sections]
needs: go-report-gh: report.GH, its Limit and the SPENT rule. go-flow-sections: flow_sections' SWARM_SECTION_BIN hand-over, the flow fixture section and cmd/swarm's section test.
touches: [bin/lib/report.py:gh, bin/lib/reports.sh:flow_sections, internal/report/gh.go:GH, internal/report/gh_state_test.go, internal/sections/flow.go:fixture, cmd/swarm/section_test.go:TestFlowGHLimit, docs/port/swarm-names.tsv:SWARM_GH_STATE row]
estimate_lines: 170
---

# flow's sections share the hourly gh limit across processes, so a Go section makes no call once an earlier section spent it, and the reverse

Needs GH and its Limit from go-report-gh, and flow_sections' hand-over and the flow fixture section from go-flow-sections. One flow run shares report.py's LIMIT, so once one section spends the hourly limit the later ones make no calls (bin/lib/report.py:179-185,218-220). A Go section runs in its own process: it cannot see LIMIT, nor set it for the sections after it. flow_sections makes a state file under TMPDIR, names it in SWARM_GH_STATE for the run and removes it after. report.py's gh, with SWARM_GH_STATE set, takes LIMIT from the file while LIMIT is empty, and writes the limit's line there once it spends it. The Go GH does the same through the store: it starts from the file's line and writes it once spent. ERROR stays per call on both sides, as each call sets it. With the variable unset both behave as now, so outcomes, dataset and every caller outside flow are unchanged. The flow fixture section makes one GH call, printing its result or Error, when its epic is gh. New SWARM_GH_STATE row in docs/port/swarm-names.tsv.

**Done when:**
- (1) A Go test in internal/report runs report.py's gh (python3 -I) and the Go GH in turn over one state file and a gh stub that logs each call and answers `API rate limit exceeded`. After the Python spends the limit, the Go makes no gh call and its Error says not tried, with the limit's line; after the Go spends it, the Python makes none. (2) The cmd/swarm section test runs the real flow_report.py with a .py section that spends the limit before the fixture (epic gh), and the stub logs no call from the fixture; with the fixture first, the later .py section makes none. (3) Each goes red when its side alone stops reading the file, shown on a worktree copy without .git. (4) go-report-gh's comparison test passes with the variable unset and set, tests/diff_run.sh --base <base> is clean on fx_flow_sections, and tests/port_swarm_names_test.sh passes. (5) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

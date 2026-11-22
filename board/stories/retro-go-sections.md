---
kind: code
status: later
epic: helpers-shared
depends_on: [go-flow-sections]
needs: go-flow-sections: the _section entry, internal/sections' registration and fixture pattern, the bin/sections/<runner>/ marker rule and reports.sh's section_bin.
touches: [internal/sections/retro.go, cmd/swarm/section_retro_test.go, bin/lib/retro_report.py:header, bin/lib/retro_report.py:names, bin/lib/retro_report.py:section loop, bin/lib/reports.sh:retro_report, tests/retro_test.sh:Go section checks, tests/diff_fixtures_retro.sh, tests/speed_list.txt:retro_sections line, docs/port/swarm-names.tsv:SWARM_SECTION_BIN row, docs/reference-logs.md:§ swarm.sh retro]
estimate_lines: 220
---

# retro's runner runs a section that has no .py file through the binary, shown with one fixture section in Go

Needs from go-flow-sections: the _section entry, internal/sections' registration and fixture pattern, the marker rule and section_bin. internal/sections gains the retro context from argv's 8 keys (bin/lib/retro_report.py:13-14) and a retro fixture section (no marker). It prints every key in order (tag, day, project, board, events, findings, memory, findings_open), the findings_open file's lines and SWARM_FINDING_REVIEWERS, as a retro_*.py section given that context prints them, and exits with n when <memory>/fixture-exit holds n. retro_report.py lists the .py names and bin/sections/retro/ markers together in name order and runs a Go section as flow_report.py does, with the same heading, error and exit rules. bash's retro_report (bin/lib/reports.sh:546-586) hands it `section_bin retro` as SWARM_SECTION_BIN, whose row in docs/port/swarm-names.tsv gains retro_report.py. retro asks gh nothing, and with no marker nothing new starts, so it still runs offline and with no binary. docs/reference-logs.md § swarm.sh retro (:1001) says a list is a retro_<name>.py or a Go section with its marker.

**Done when:**
- (1) A Go test in cmd/swarm runs the real retro_report.py over a temp tree with two retro .py sections and the fixture's marker, with the test binary as SWARM_SECTION_BIN. The fixture's `## ` line sits in name order; its 8 keys, the findings_open lines and SWARM_FINDING_REVIEWERS equal what a .py section printing them gives; with fixture-exit holding 3 it prints `error: <name>: exit 3` and the later section still runs. (2) tests/retro_test.sh, from outside on a plugin copy with the marker added, shows the fixture through swarm.sh retro. With SWARMDEV_BIN naming a missing file, the fixture prints `error:` with the binary's line and the .py sections still run; with no marker and SWARMDEV_BIN missing, retro prints what it prints now. (3) Each check goes red when its rule is broken, shown on a worktree copy without .git. (4) tests/diff_run.sh --base <base> is clean on fx_retro_sections, and tests/speed_list.txt names it. (5) tests/port_swarm_names_test.sh passes, go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

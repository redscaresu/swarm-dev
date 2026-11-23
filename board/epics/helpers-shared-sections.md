---
status: later
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
parent: helpers-shared
depends_on: [foundation-exit, helpers-shared-base, helpers-shared-report]
---

# The flow and retro runners run Go sections, and two of report's inline sites call the binary

flow_report.py and retro_report.py hand a section that has no .py file to the binary. archive_session and codex_story_prompt call the binary.

A child of [helpers-shared](helpers-shared.md), split on 2026-11-23. The parent's constraints and its shared rules (L2, the P rules) apply here unchanged.

**Done when:** flow_report.py and retro_report.py run a section with no .py file through the binary, in the same name order, under the same heading and with the same context. One fixture section in Go shows it for each runner. A gh limit that one side spends is seen as spent by the other, Python and Go alike. bin/lib/lifecycle.sh's archive_session and bin/swarm.sh's codex_story_prompt run the binary, and the differential run is clean for their fixtures.

**Stories:**
- [go-flow-sections](../stories/go-flow-sections.md)
- [retro-go-sections](../stories/retro-go-sections.md)
- [gh-limit-handover](../stories/gh-limit-handover.md)
- [archive-session-binary](../stories/archive-session-binary.md)
- [codex-declines-binary](../stories/codex-declines-binary.md)

**Out of scope:**
- Porting any real flow or retro section (helpers-reports, helpers-flow-*)

**Your part:**
- None beyond the parent's: L2 patches.

**Areas:**
- go-flow-sections: [internal/sections/sections.go, internal/sections/flow.go, internal/sections/sections_test.go, cmd/swarm/section.go, cmd/swarm/section_test.go, bin/ported/_section, bin/lib/flow_report.py:header, bin/lib/flow_report.py:names, bin/lib/flow_report.py:section loop, bin/lib/reports.sh:section_bin, bin/lib/reports.sh:flow_sections, bin/lib/binary.sh:binary_path, tests/flow_sections_test.sh, tests/diff_fixtures_flow.sh, tests/speed_list.txt:flow_sections line, docs/port/swarm-names.tsv:SWARM_ROWS row, docs/port/swarm-names.tsv:SWARM_DEPS row, docs/port/swarm-names.tsv:SWARM_STORIES row, docs/port/swarm-names.tsv:SWARM_SECTION_BIN row, docs/reference-logs.md:§ Flow and features, docs/port/README.md:§ The markers]
- retro-go-sections: [internal/sections/retro.go, cmd/swarm/section_retro_test.go, bin/lib/retro_report.py:header, bin/lib/retro_report.py:names, bin/lib/retro_report.py:section loop, bin/lib/reports.sh:retro_report, tests/retro_test.sh:Go section checks, tests/diff_fixtures_retro.sh, tests/speed_list.txt:retro_sections line, docs/port/swarm-names.tsv:SWARM_SECTION_BIN row, docs/reference-logs.md:§ swarm.sh retro]
- gh-limit-handover: [bin/lib/report.py:gh, bin/lib/reports.sh:flow_sections, internal/report/gh.go:GH, internal/report/gh_state_test.go, internal/sections/flow.go:fixture, cmd/swarm/section_test.go:TestFlowGHLimit, docs/port/swarm-names.tsv:SWARM_GH_STATE row]
- archive-session-binary: [cmd/swarm/session_log.go, bin/ported/_session-log, bin/lib/lifecycle.sh:archive_session, docs/port/sites.tsv:archive_session row, docs/port/copies.tsv:archive_session row, tests/diff_fixtures_archive.sh, tests/nopy_list.txt:fx_archive_session line, tests/lib_path_test.sh:_archive check, tests/speed_list.txt:archive_session line]
- codex-declines-binary: [internal/review/declines.go, internal/review/declines_test.go, cmd/swarm/declines.go, bin/ported/_declines, bin/swarm.sh:codex_story_prompt, docs/port/sites.tsv:codex_story_prompt row, docs/port/copies.tsv:codex_story_prompt row, docs/port/swarm-names.tsv:SWARM_LIB row, tests/diff_fixtures_codex.sh, tests/codex_test.sh:declines checks, tests/speed_list.txt:codex_declines line]

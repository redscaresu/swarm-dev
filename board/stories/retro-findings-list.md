---
kind: code
status: blocked
epic: retro-report
depends_on: [retro-command]
needs: [retro-command (the section runner and its findings_open context file; written from `out_of_scope_findings <window day>`)]
touches: [bin/lib/reports.sh:out_of_scope_findings, bin/lib/retro_findings.py, tests/retro_findings_test.sh, docs/reference-logs.md:findings paragraph (swarm.sh retro part)]
estimate_lines: 80
easy: true
---

# retro's findings list: declined out-of-scope and deferred findings that no story carries

Needs from retro-command: the section runner and its findings_open context file. Add retro's findings section. It lists the findings declined as out-of-scope or deferred since the window's day, where the newest row is still that decline and no story carries the text. Each line shows its reason, date, kind, PR and text. retro_report already calls `out_of_scope_findings <window day>` (bin/lib/reports.sh:93-113) and writes the output to findings_open. Make the function honour that optional day argument. With no argument it keeps IDLE_FINDING_DAYS for idle_lines (bin/lib/board.sh:783). Do not write a second copy of its story-carries-text rule, and do not edit retro_report or retro_report.py. Add bin/lib/retro_findings.py, which prints findings_open under `## findings`. If the file is empty, it prints a line saying none were found since <tag>. Docs: fill only the **findings** stub paragraph that retro-command wrote in docs/reference-logs.md's `### swarm.sh retro` part, and leave the other paragraphs alone. One sentence per line in docs (the coming 150-word line cap, board/stories/doc-line-cap.md).

**Done when:**
- tests/retro_findings_test.sh (new) builds a fixture findings.tsv with six declines: an out-of-scope one and a deferred one since the tag, one from before the tag's day, one later logged --filed, one later fixed, and one whose text a board story carries. `swarm.sh retro` lists exactly the first two, each with its reason.
- tests/next_test.sh passes with no change to it, so idle_lines keeps its 30-day window. The new test fails on a worktree copy that ignores the since argument, and the PR body has the FAIL lines.
- shellcheck and scripts/select-tests.sh --run pass.

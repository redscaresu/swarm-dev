---
kind: code
status: later
epic: helpers-dropped-lines
depends_on: [dropped-lines-merged-parent]
needs: dropped-lines-merged-parent (outside this epic): the merged-parent fixture records sides() and merged_parent as that fix leaves them.
touches: [tests/dropped_lines_test.sh:byte cases (a block after the extends cases), tests/diff_fixtures_dropped.sh:fx_dropped_octopus, fx_dropped_merged_parent, fx_dropped_merge_unchecked, tests/diff_fixtures_dropped.sh:dropped_stubs (commits/<sha>/pulls)]
estimate_lines: 280
---

# Cases and fixtures pin the bytes dropped-lines prints and the helper answers no fixture reaches

Tests-only, port: true, on main's Python. (a) tests/dropped_lines_test.sh: a block of scan() cases after the extends cases (after line 499), away from the header, scan() and the usage checks that dropped-lines-entry edits. The cases: bytes 01 and 7f taken off a printed line; a 310-character line cut to 300, counted in characters (299 ASCII then two é keeps one é); e2 82 then A prints one U+FFFD then A, ff fe then A two, ed a0 80 then A three (Python's utf-8 'replace' gives one U+FFFD per maximal invalid subpart: checked with python3 on 2026-11-22); a file whose name git quotes (a tab and a double quote) printed unquoted; a name with a space printed with no trailing tab (dropped_lines.py:201); a name with é printed as is (core.quotePath=false); a line of only U+00A0 is not blank and prints (bytes.strip() strips ASCII only); a head line joining a dropped line's words with U+00A0 does not extend it (bytes.split() splits on ASCII only); a dropped last line with no newline at end of file prints; two spare head lines that extend one dropped line, the first in the head file's order taken (dropped_lines.py:368). (b) tests/diff_fixtures_dropped.sh: dropped-lines on an octopus merge (its stop line, exit 2); dropped-lines on a stacked build's merge of a merged parent whose merge drops a line (dropped_stubs answers commits/<sha>/pulls); merge on a story PR whose merge is an octopus (held 'dropped base lines unchecked', with the board state's protected: entry, its time masked as fx_dropped_merge_own_story does). Today's four fixtures reach one own merge only (tests/diff_fixtures_dropped.sh:30,84,115-132).

**Done when:**
- (1) Every new case passes on main's Python. (2) On a worktree copy without .git, each case goes red with its rule broken in bin/lib/dropped_lines.py, the FAIL lines in the PR body: CONTROL emptied (control bytes); the cut taken on bytes (é); decode with 'ignore' (the three U+FFFD cases); unquote returning the path as given (the quoted name); the tab trim dropped (the name with a space); the blank check and extends run on decoded text (both U+00A0 cases); the 'No newline' line counted as context (its case); the pool iterated in sorted order (the order case). (3) tests/diff_run.sh between two copies of the tree is clean on each new fixture, and exits 1 naming the fixture when copy b's octopus stop text, merged-parent check or hold text is changed. (4) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: code
status: blocked
epic: retro-report
depends_on: [retro-command, retro-recurring-extract]
needs: [retro-command (the section runner and its context (window day; findings.tsv path; board dir)), retro-recurring-extract (bin/lib/recurring.py's check_story and the PR counts with since and min parameters)]
touches: [bin/lib/recurring.py:fold map, bin/lib/retro_recurring.py, tests/retro_recurring_test.sh, docs/reference-logs.md:recurring paragraph (swarm.sh retro part)]
estimate_lines: 160
easy: false
---

# retro's recurring list: kinds fixed on 3+ PRs since the tag, after folding, that have no check

Needs from retro-command: the section runner and its context. Needs from retro-recurring-extract: recurring.py. Add bin/lib/retro_recurring.py. It lists each kind fixed or escaped on 3 or more distinct PRs since the window's day, after folding, that has no check. The fold: docs, docs-misstate-code, stale-docs and docs-stale count as docs. test-gap, test-coverage and missing-case count as test-gap (HLD Appendix A, board/hld/2026-10-25-swarm-dev-0-28.md:748-754). A folded kind has a check when check_story finds a merged `checks:` story for any name in its group. Each row shows the folded kind, the names folded into it, and its PR count. Put the fold map in recurring.py. outcomes' own recurring block stays unfolded. The kinds whose check stories wait in open PR #547 show here until those stories merge. If nothing is found, print a line saying so. Docs: fill only the **recurring** stub paragraph that retro-command wrote in docs/reference-logs.md's `### swarm.sh retro` part, and leave the other paragraphs alone. One sentence per line in docs (the coming 150-word line cap, board/stories/doc-line-cap.md).

**Done when:**
- tests/retro_recurring_test.sh (new): docs-misstate-code fixed on 2 PRs and stale-docs on a third since the tag gives one `docs` row with 3 PRs that names both kinds. A kind fixed on 2 PRs is absent.
- Same test: a kind fixed on 3 PRs is absent when a merge on the fixture board's origin/HEAD deleted its `checks:` story.
- tests/recurring_kinds_test.sh passes with no change to it, because outcomes does not fold. The new test fails on a worktree copy with the fold map emptied, and the PR body has the FAIL lines.

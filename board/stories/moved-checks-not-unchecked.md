---
kind: code
status: ready
epic: board-pr-and-briefs
depends_on: []
touches: [bin/lib/reports.sh:fail_lines, tests/fail_lines_test.sh:moved check cases, docs/reference.md:rules-unchecked text]
estimate_lines: 65
easy: true
---

# rules-unchecked skips a check moved from one file to another

fail_lines (bin/lib/reports.sh:513-561) prints `rules-unchecked: <test> has no FAIL line in the PR body` for every test named on a line the PR's diff adds, so a moved check counts as new: #524 drew 44 fixed and 158 declined findings, most of them moved checks (v0.28.0 retro). Skip a test whose added line matches a line the same diff removes (another file, or elsewhere in the same file), compared with leading and trailing whitespace stripped; a check added with no removed twin still needs its FAIL line. docs/reference.md's rules-unchecked text (:1822-1826, The outer loop) says a moved check is skipped.

**Done when:**
- tests/fail_lines_test.sh gains a diff that moves a check between two test files (no rules-unchecked line) and one that adds a new check beside a moved one (one line, for the new check). The first fails with the skip removed.
- docs/reference.md's rules-unchecked text names the moved-check rule.

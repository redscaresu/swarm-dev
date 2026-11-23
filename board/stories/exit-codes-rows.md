---
kind: docs
status: later
touches: [docs/port/exit-codes.tsv]
estimate_lines: 20
easy: true
---

# exit-codes.tsv: the gh shim pass-through row and symbol names

From the v0.32.0 retro (#1033). docs/port/exit-codes.tsv has no row for the gh shim passing a nonzero gh code through (bin/gh-shim/gh, pinned by tests/gh_calls_test.sh). Its named-code rows (wait 3, 4, 5 and _step-up 4) omit the symbol names the code uses. Add the row and the names.

**Done when:**
- exit-codes.tsv has a row for the shim's pass-through and a symbol name on each named-code row, and each name exists in bin/.
- tests/doc_check_test.sh passes.

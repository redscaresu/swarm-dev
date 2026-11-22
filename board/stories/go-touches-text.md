---
kind: code
status: later
epic: helpers-shared
depends_on: []
touches: [internal/touchesrows/text.go, internal/touchesrows/text_compare_test.go]
estimate_lines: 200
---

# touches_rows' text rules run as Go: front matter pairs, first word, overlap and depends_on

internal/touchesrows: Pairs, FrontText, SkipWords, FirstWord, Overlap and Deps as bin/lib/touches_rows.py:4-19,66-85 has them. Each key's first value has its leading spaces dropped; CRLF is tolerated; there is front matter only when the first line is ---. FirstWord gives the first word past §, #, the, a and an as it is written: only the check against those words lower-cases it, with Python's lower() (:75), so Foo and foo are two words and do not clash. With nothing past them it gives the last word. Words split as Python's str.split() splits, which also splits on U+001C to U+001F, where Go's unicode.IsSpace does not. A bare file clashes only with a bare file. depends_on splits on spaces, commas, brackets and quotes, before a #. FrontText takes text already decoded; reading files is go-touches-files'. A comparison test runs the Python and the Go over the same inputs, byte for byte: CRLF, no closing ---, repeated keys, a key with no value, '§ The x', 'A', Foo against foo, 'THE Foo' against 'the foo', a word split by U+001F, depends_on with a comment, and the front matter and touches tests/board_state_test.sh and tests/concurrency_check_test.sh give touches_rows. The module's __main__ script (touches_rows.py:104-217) stays Python: see contradictions.

**Done when:**
- (1) The comparison test passes. (2) It goes red when FirstWord alone skips no articles, when FirstWord alone returns the lower-cased word, and when touches_rows.py's overlap alone lets a bare file clash with its parts, each shown on a worktree copy without .git. (3) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: code
status: ready
epic: telemetry-readers
depends_on: []
touches: [bin/lib/agents.sh:append_event (fields, separator, strip, EVENT_SEP, EVENT_OUTCOME_AWK), bin/lib/events_outcome.py (new), tests/events_test.sh:logged (stripped outcome), tests/events_test.sh:helper cases (new), docs/reference-logs.md:Logs and outcomes (the field tail), tests/doc_check_known.txt:events_outcome entry (only if doc_check_test asks)]
estimate_lines: 180
easy: false
---

# append_event takes key=value fields; one outcome helper for Python and awk

No depends_on. append_event (bin/lib/agents.sh:874-879; the epic's 857-861 is stale) takes optional key=value fields after the outcome and writes them inside column 5, after a separator this story picks: a token no live outcome holds (` | ` is out: 11 of 13,762 live outcomes hold it). It strips the separator from the outcome text first. Keys match [a-z_]+; values hold no space, tab or separator; the story picks and pins what an invalid pair does, and the line itself is always written. The separator is defined once per language: EVENT_SEP in agents.sh, SEP in the new bin/lib/events_outcome.py (outcome(row) -> text, fields(row) -> dict). Beside append_event, the awk function outcome(s) kept as shell text EVENT_OUTCOME_AWK, which wave-2 stories put in front of each awk program (a function, not a prefilter: wait --lead's resend_pass reads the log every poll, lifecycle.sh:4219-4222, and a prefilter would read it twice). tests/events_test.sh's logged() (234-239) compares the stripped outcome through that function and keeps its NF == 5, ISO-Z and actor pins. No reader moves and no caller passes fields here (telemetry-writers). New top-level code, so select-tests runs the full suite.

The awk outcome() uses only POSIX index/substr/length, so BSD awk (macOS) and CI's Linux awk agree. Round-trip cases include an internal and a repeated separator in the free text, with and without fields, in both Python and awk.

**Done when:**
- events_test.sh: `append_event x t 'ok (round 2)' round=2 verdict=pass` writes one row of 5 tab fields whose column 5 is exactly the outcome, the separator, then `round=2 verdict=pass`.
- An outcome that ends in the separator (a die message) is written without it: outcome() returns the text and fields() returns {}.
- Helper cases with exact expected values: an untailed row (outcome == row[4], fields == {}), a tailed row, an untailed outcome holding `=`, and a herdr JSON outcome, the last two read back unchanged with fields {}; the awk outcome() returns the same text as the Python one for each row.
- A case pins EVENT_SEP equal to events_outcome.SEP, and one shows what an invalid key or value does, with the outcome line still written.
- docs/reference-logs.md § Logs and outcomes states the tail: separator, key and value rules, readers strip it, older rows have none (humanizer pass on it).
- Breaking outcome() to return row[4] (copy aside, copy back) turns the helper cases red.
- The Python and awk helpers return the same outcome for each inline case, including an internal and a repeated separator, with and without fields; the case test runs under CI's Linux awk and passes locally under macOS awk.
- The awk helper uses no gawk-only function (no match() with an array, gensub, or asort).

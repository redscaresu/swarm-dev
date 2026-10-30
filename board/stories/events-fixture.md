---
kind: code
status: ready
epic: telemetry-readers
depends_on: []
touches: [tests/fixtures/events/redact.py (new), tests/fixtures/events/v029-sample.tsv (new), tests/events_tail_helpers.sh (new), tests/events_fixture_test.sh (new)]
estimate_lines: 190
easy: false
risk: high
---

# A redacted v0.29 events.tsv fixture and the tail-equivalence harness

No depends_on. New tests/fixtures/events/redact.py <events.tsv> <cut> writes a redacted sample, allowlist-shaped (rules.md: never a denylist): it keeps times, column 2, numbers, punctuation and words found in the plugin's own source (bin/, hooks/, scripts/), and swaps every other token by class for a deterministic stand-in: a-z for a slug (the same slug, the same stand-in, so joins on target hold), a stand-in pane id, the same URL shape on `o/r`, `/p/...` for a path. The builder runs it once on the main checkout's .swarm/events.tsv (gitignored, .gitignore:2; not a session log) with cut 2026-10-29T01:14:39Z, v0.29.1's tag commit time: 37 of the 11,415 rows before it hold `=` (v0.29.0's tag has 34). Sample: every `=` row, one row per (command, first word of outcome) pair (about 304 pairs), and every row of three whole story lifecycles; at most 400 rows, in tests/fixtures/events/v029-sample.tsv. New tests/events_tail_helpers.sh, sourced like tests/merge_fixture.sh: build a stand-in project from an events file, with an optional tail appended to column 5 of every row, and same_output, which runs one command in two projects and fails on any difference or on an empty first output. New tests/events_fixture_test.sh checks both. No test reads the live log; the PR gives the cut and the counts, never live rows. estimate_lines counts code; the fixture adds up to 400 data rows.

Lead decisions (2026-10-30): the fixture is cut at v0.29.1's tag (37 `=` outcomes), and its file name and description say v0.29.1, not v0.29.0. URLs become the same shape on the fake repo `o/r`, so the URL-parsing reads still run; no real owner, repo or PR number survives. Every slug and pane id is replaced by field position, whatever its spelling, even when the word also appears in the plugin's source.

**Done when:**
- events_fixture_test.sh: every fixture row has 5 tab fields and an ISO-Z time; exactly 37 outcomes hold `=`; at most 400 rows.
- events_fixture_test.sh: every token of every fixture row falls in redact.py's allowlist classes; a row with a slug-like word outside the source vocabulary, a `/Users/` path or a github.com URL off `o/r`, added to a copy of the fixture, turns it red.
- redact.py over a synthetic log in a temp dir maps one slug to one stand-in across rows, a URL to `o/r` and a path to `/p`, and a second run writes the same bytes.
- same_output fails for a command printing column 5 over a project and its tailed copy, passes for one printing columns 1-4, and fails when the first output is empty.
- Breaking redact.py's URL rule (copy aside, copy back) turns the synthetic case red.
- The fixture's name and description say v0.29.1, and its `=` outcome count matches v0.29.1's cut.
- A test feeds the redactor a row whose slug is also a word in the plugin's source, and the slug is replaced; no /Users path, real pane id, real slug or URL outside `https://github.com/o/r/` is left in the fixture (the test fails on a planted one).

---
kind: code
status: blocked
blocked_by: [outcomes-story-columns, cost-since, review-yield-report, session-log-reads-archive]
epic: training-export
depends_on: [outcomes-story-columns, cost-since, review-yield-report, session-log-reads-archive]
touches: [bin/swarm.sh:export_report (new), bin/swarm.sh:dispatch (export arm), bin/swarm.sh:usage header (export line), bin/swarm.sh:READ_ONLY_COMMANDS, tests/export_test.sh (new), tests/events_test.sh (RO_EXPECTED), docs/method.md (:364 read-only list; export columns after § decisions), README.md (command table)]
risk: high
---

# swarm.sh export [--since YYYY-MM-DD] [--format jsonl|tsv] writes one row per build attempt for training a router, with no free text

New export_report in the REPORT_PY style that runs outcomes_report (as decisions does, bin/swarm.sh:1081-1094) and reads its rows by column name; no second parser of agents.tsv, events.tsv or session logs. It adds project (the project directory's name), keeps a fixed allowlist of columns in a documented order (project, slug, epic, kind, risk, role, model, effort, started, the four tokens_*, cost_usd, tells_findings/nudge/resume, findings fixed/declined and by reviewer, escalate_at, dialog_at, dialog, escalated_at, reset_at, drop_at, close_cause, pr, pr_state, merged_at, attempt, story_merged), and checks every value against its column's type (slug, enum, integer, decimal, UTC time, PR URL); a value that fails is emitted empty (null in jsonl) with a warning on stderr. jsonl is the default, typed (ints, floats, bools, null); tsv has a header. --since passes through to outcomes (attempt numbers stay stable). Read-only: add export to READ_ONLY_COMMANDS (:4271) and tests/events_test.sh RO_EXPECTED (:137). Document every column (name, type, source) in docs/method.md after § decisions (:385-394) and in the read-only list (:364); README command-table row (after :80); usage header line. decisions_report's output is not reused: it carries story and finding text (:1112, :1131).

**Done when:**
- tests/export_test.sh: a fixture project (stub gh, session logs, agents/events/findings) with a one-attempt merged story, a retried story (two builders, #1 CLOSED, #2 MERGED) and an escalated story (two code attempts then escalate; escalate, dialog, escalated, reset events): `export --format tsv` has exactly the documented header and every column of every row equals its pinned value; `export` (jsonl) gives the same values typed.
- Row count equals the fixture's agents.tsv builder lines; `--since` drops earlier rows and keeps attempt numbers.
- SENTINEL-TEXT placed in a finding's text, a reset reason, a dialog outcome `ok (SENTINEL-TEXT)`, a .swarm/briefs file, a reply file, the story body and a failed command's die message appears in neither format; the PR shows this check failing with the per-column type check removed.
- `export --format csv`, `export --since 2026-1-1` and `export bogus` exit non-zero with the usage line; export writes no events.tsv line (events_test passes with export in RO_EXPECTED).
- docs/method.md lists every exported column with its type and source, matching the tsv header (the test diffs the header against the doc's list); README and the usage header name export.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass; humanizer ran over the README/method.md prose and the PR description, and the PR says so.

**From review (binding; overrides the scope above where they differ):**
- Plant SENTINEL-TEXT in passthrough columns too (front matter risk and kind, an agents.tsv model or effort) and assert it appears in neither format, those cells come out empty, and a warning goes to stderr; this is the check the PR shows failing without the type check.
- Every column has a type: slug (also for project), enum, integer, decimal, UTC time, PR URL, bool true|false|empty, reviewer pairs `^([a-z-]+:[0-9]+( |$))*$`, model as a token `^[a-z0-9][a-z0-9.-]*$`. Pin one of each, including a model no enum knows.
- Depends on session-log-reads-archive as well; export_test has an archive-only fixture.

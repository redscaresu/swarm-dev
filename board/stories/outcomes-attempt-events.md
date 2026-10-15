---
kind: code
status: blocked
blocked_by: [outcomes-every-attempt, close-holds-a-stopped-story, session-log-reads-archive]
epic: training-export
depends_on: [outcomes-every-attempt, close-holds-a-stopped-story, session-log-reads-archive]
touches: [bin/swarm.sh:outcomes_report (pass 1), tests/outcomes_test.sh, tests/decisions_test.sh]
risk: high
---

# outcomes gives each attempt its UTC start, tokens by type, and only its own tells, close cause and escalation steps

Pass 1 of outcomes_report (bin/swarm.sh:997-1043). Append columns after attempts, never reorder (decisions reads by name, :1088-1094): started (the session log's first `timestamp`, UTC ISO; empty with no log), tokens_input, tokens_cache_write, tokens_cache_read, tokens_output (session_usage's split, :816-835, which today is summed and dropped, :1037-1038), close_cause, escalate_at, dialog_at, dialog, escalated_at, reset_at, drop_at. Today tells and closes are counted per slug across all attempts (:1013-1041), so a retried story repeats them. Attribute each ok events.tsv line (target slug or agents.tsv name) to one attempt: escalate and dialog go to the slug's escalate-role attempt that started nearest them (escalate is logged before the Fable session starts, :1848); every other line to the slug's latest attempt started at or before it; an attempt with no session log starts at its agents.tsv day. close_cause is the cause of the attempt's last close:<cause> (bare close: empty). dialog is accepted or dismissed parsed from `ok (<x>)`, empty otherwise. Never read field 5 of reset or drop (the lead's free-text reason, :4326).

**Done when:**
- tests/outcomes_test.sh: a retried slug (session first timestamps 10:00Z and 14:00Z) with tell:findings at 11:00Z and 15:00Z and close:stalled at 12:00Z prints tells_findings 1 and 1 (not 2 and 2), closes 1 and 0, close_cause stalled and empty.
- started equals each fixture session's first timestamp; a builder with no session log has empty started and its events still land by its agents.tsv day.
- The four tokens_* columns equal the fixture's per-type usage and sum to tokens.
- An escalated slug (two code attempts, then an escalate-role attempt; escalate at 09:59Z before its session's first line at 10:00Z, dialog ok (accepted), escalated, reset ok (SENTINEL-REASON)) fills escalate_at, dialog_at, dialog=accepted, escalated_at and reset_at on the escalate row only; the code rows have them empty; SENTINEL-REASON is absent from the output; a dialog `ok (anything else)` gives an empty dialog.
- The first 17 header columns are unchanged and tests/decisions_test.sh passes (updated only where a retried slug's tells now count per attempt).
- The PR shows the per-attempt and escalate checks failing with the attribution removed (counted per slug); shellcheck and every tests/*_test.sh pass.

**From review (binding; overrides the scope above where they differ):**
- Depends on session-log-reads-archive: started and tokens read through its gzip-aware reader. Done when: with only the .gz copy present, started, tokens_* and cost are still filled.
- An event is ok when field 5 is exactly 'ok' or starts with 'ok ('; field 5 is read only for that prefix and for dialog's accepted|dismissed; nothing else in it is copied.
- Events attach to the escalation cycle open when they were logged (by event order: from an escalate to the next reset, drop or escalate of the slug), never by nearest session start. For repeats within one attempt, take the last. A log-less attempt starts at <agents.tsv day>T00:00:00 in the local zone converted to UTC, and the docs say so.
- Fixtures: two escalation cycles of one slug separated by a reset, with a dialog answered late in the first, attach to the first; a drop case with `drop ok (SENTINEL-REASON)` fills drop_at and SENTINEL-REASON appears nowhere.

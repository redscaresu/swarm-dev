---
status: active
---

# The swarm's runs export as one clean dataset for training a model-and-effort router

**Done when:**
- `outcomes` gives each build the PR that build made (board story outcomes-every-attempt, absorbed).
- `swarm.sh export [--since YYYY-MM-DD] [--format jsonl|tsv]` writes one row per build attempt: project, slug, epic, kind, risk, role, model, effort, started (UTC), tokens by type, cost at list price, tells by kind, findings fixed and declined (by reviewer once review-yield logs it), escalation steps with their UTC times (escalate, dialog, escalated, reset, drop), close cause, PR, PR state, merged-at, attempt number, and whether the story finally merged. Columns are documented in docs/method.md; a fixture project pins every column, including an escalated story and a retried one.
- The export holds no secrets or prompt text: only ids, enums, numbers, times and URLs; a test fails if a free-text field (finding text, brief, reply) appears.
- `swarm.sh cost` refuses an argument it does not understand (today `cost --since 2026-10-15` silently prints the all-time total); `cost --since YYYY-MM-DD` works as `outcomes --since` does.
- Running export over swarm-dev and infrafactory produces files the lead reads back: row counts match agents.tsv builder lines, and the lead posts the counts on the epic's lead story.

**Out of scope:** training the router. Uploading the data anywhere. Scoring prompts.

**Constraints:** bash 3.2 plus python3 in the REPORT_PY style; read-only over .swarm logs and session .jsonl; reuse outcomes_report and the REPORT_PY helpers rather than a second parser; not decisions_report, whose output carries story and finding text. events.tsv field 5 holds free text for reset, drop and failed commands (docs/method.md says it holds no message contents; the export story corrects that line), so it is read only through enum and prefix parses. Bump plugin.json in a release story.

**Checks before every stage:** every PR passes shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .`; shows each new check failing with its code removed; and ran humanizer over changed README/docs prose and its description, saying so.

**Your part:** none; the user approved the stories on 2026-10-15.

## Counts (training-export-counts, 2026-10-16)

`swarm.sh export` from main at #182, run from each project's root into the lead's scratchpad (not committed).

| project | agents.tsv builder lines | jsonl rows | tsv rows | empty started | empty pr | session from archive |
|---|---|---|---|---|---|---|
| swarm-dev | 76 | 76 | 76 | 0 | 4 | 0 |
| infrafactory | 132 | 132 | 132 | 0 | 1 | 0 |

Every jsonl line parses, and every tsv row has the header's 33 columns, with the same names as the jsonl keys. Three finding texts sampled from each project's findings.tsv (first, middle and last line) appear in neither file. The rows with no PR are builds that opened none. In swarm-dev those are pin-claude-version (verify), goal-spike-a (a spike), fable-check (an escalate check) and the first wait-until-report build, closed as stalled. In infrafactory it is dash-readable. No session log has been deleted yet, so no row read close's archive copy. That path is covered by cost_test and outcomes_test.

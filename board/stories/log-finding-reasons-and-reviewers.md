---
kind: code
status: ready
epic: leaner-faster-swarm
depends_on: []
touches: [bin/swarm.sh:FINDING_REVIEWERS, finding_flags, record_finding, REPORT_PY comment, finding_rule, docs/method.md:§ Building outer loop, tests/lessons_test.sh, tests/review_yield_test.sh, tests/events_test.sh:log-finding cases, tests/epic_test.sh:finding_rule checks]
---

# log-finding records escaped defects, the plan reviewers, and why a finding was declined

Add three values to FINDING_REVIEWERS (bin/swarm.sh:795). escaped is a defect a later fix found in merged work, logged against the original PR with the existing kind-then-PR order: `log-finding --reviewer escaped <kind> <original PR URL> '…'`. skeptic and critic log plan-review findings on a board PR; codex is already there. finding_flags (:801-812) reads `--declined <reason>` into FINDING_REASON and counts the reason in FINDING_SKIP, so main's events target (:5590-5592) stays `<kind> <pr>` and is still logged as log-finding:declined. The reason is out-of-scope, nit or wrong; a missing or other reason fails naming the three, before anything is written. record_finding (:816-835) writes the reason as a 7th field on declined rows, and its usage message shows `--declined <reason>`. Fixed rows stay at 6 fields, and finding_rows already ignores fields past the sixth, so lessons, review-yield, outcomes and dash read both. Leave dispatch's log-finding arm unchanged (the reason travels in FINDING_REASON; dispatch is flow-and-features' in wave 1), and leave the header's log-finding line to scoped-parallel-reviews in wave 2 (flow-and-features deletes the export line next to it). finding_rule (:1921-1937) gives the new syntax, says when to use each reason (out-of-scope: outside the story's touches and **Done when**) and when to log escaped, and drops 'for decisions'; the comments on FINDING_REVIEWERS, record_finding and REPORT_PY lose decisions too. docs/method.md: only the **Learning across epics (the outer loop).** paragraph (:623-643): its log-finding lines, and 'and `decisions` exports both'. Leave commands/swarm.md's story arm to backlog-conductor, which replaces it. bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- tests/lessons_test.sh: `log-finding --reviewer escaped k <pr> t`, `--reviewer skeptic …` and `--reviewer critic …` each append a row with that reviewer in field 6.
- `log-finding --declined nit --reviewer codex k <pr> t` appends a 7-field row ending `declined<TAB>codex<TAB>nit`; `--declined --reviewer codex …` and `--declined maybe …` exit non-zero naming out-of-scope, nit and wrong, and append nothing.
- tests/review_yield_test.sh: a findings.tsv that mixes 4-, 6- and 7-field rows gives the old rows the same counts as before.
- tests/events_test.sh: `log-finding --declined out-of-scope --reviewer codex k <pr> t` is logged as log-finding:declined with target `k <pr>`.
- finding_rule's text names out-of-scope, nit, wrong and `--reviewer escaped`, and a new check in tests/epic_test.sh fails if finding_rule's text or the outer-loop paragraph of docs/method.md has a `--declined` not followed by a reason. It fails on today's files.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.

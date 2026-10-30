---
kind: code
status: blocked
epic: review-rounds-end
depends_on: [intervene-cause]
needs: [intervene-cause: orders the shared bin/swarm.sh usage block; this story edits it after intervene's line changes]
touches: [bin/lib/reports.sh:FINDING_REASONS, bin/lib/reports.sh:out_of_scope_findings (deferred rows, reason passed on), bin/lib/reports.sh:record_finding doc comment (filed row), bin/lib/reports.sh:reviewers doc comment (by-round header), bin/lib/board.sh:idle_lines (finding label), bin/lib/flow_reviewers.py:REASONS (deferred column), bin/swarm.sh:usage (log-finding line), commands/swarm.md:idle findings bullet (step 1), docs/method.md:planning chain idle candidates, docs/reference-logs.md:The outer loop (reasons), docs/reference-logs.md:log-finding row, docs/reference-logs.md:reviewers by-round paragraph, tests/log_finding_test.sh:REASONS, tests/epic_codex_test.sh:bare_declined, tests/review_yield_test.sh:by-round header, tests/next_test.sh:idle findings cases]
estimate_lines: 90
easy: true
---

# log-finding accepts --declined deferred, and next's idle lines and flow reviewers read it

Needs nothing from another story. FINDING_REASONS (bin/lib/reports.sh:16) gains deferred, so `log-finding --declined deferred` is accepted and logged like the other reasons; its refusal lists all four. Every site that lists what log-finding accepts says so in this PR: the usage line (bin/swarm.sh:20, also its --filed clause: an out-of-scope or deferred one), docs/reference-logs.md's log-finding row (:713, moved there by #760) and § The outer loop (:676: deferred is a finding the round cap held back from round 3), and reports.sh's comments on record_finding's filed row (:47-49) and out_of_scope_findings (:81-87). out_of_scope_findings (reports.sh:89-100) takes declined rows whose reason is deferred as it takes out-of-scope ones (its awk at :98), keeping the newest-row rule, so `log-finding --filed` drops a deferred text as it drops an out-of-scope one; it passes each row's reason on, and idle_lines (bin/lib/board.sh:652-665) labels each line `<reason> finding:`, so an out-of-scope row still prints `out-of-scope finding:` byte for byte. commands/swarm.md step 1's idle bullet (:116-124) and docs/method.md:38 say deferred findings are offered too. flow reviewers' by-round block gains a deferred column: REASONS (bin/lib/flow_reviewers.py:114), its doc (reports.sh:387) and docs/reference-logs.md:580. Leave finding_rule and the review brief's decline rule to round-cap, which first sends the reason, and commands/plan-epic.md:110, commands/plan-hld.md:163 and tests/plan_epic_test.sh:85 as they are (contradictions 2 and 3). Bash 3.2; humanizer over the changed docs.

Lead decision (2026-10-30): plans have no round cap, so `deferred` is not a plan reason. commands/plan-epic.md, commands/plan-hld.md and tests/plan_epic_test.sh keep their reason lists; the epic's Done when is amended to say so.

**Done when:**
- tests/log_finding_test.sh: `log-finding --declined deferred --reviewer codex --round 3 k o/r#94 t` writes a row whose seventh field is deferred and eighth is 3, and the refusal for `--declined maybe` names `out-of-scope nit wrong deferred`; proven by removing deferred from FINDING_REASONS in a worktree copy (red).
- tests/next_test.sh: on an idle project, a deferred decline from the last 30 days prints `  deferred finding: <date> <kind> <PR>: <text>`; after `log-finding --filed` with its text it is gone; an out-of-scope decline still prints `  out-of-scope finding: ...` unchanged.
- tests/review_yield_test.sh: flow reviewers' by-round header is `round reviewer fixed declined nit out-of-scope wrong deferred share_fixed` and a deferred row counts 1 in its column and in declined.
- tests/epic_codex_test.sh's bare_declined accepts `--declined deferred`; scripts/select-tests.sh --run passes, including tests/doc_check_test.sh.

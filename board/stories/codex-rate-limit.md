---
kind: code
status: ready
epic: reliable-runs
depends_on: []
touches: [bin/swarm.sh:CODEX_LIMIT_RE, bin/swarm.sh:codex_review (limit branch), bin/swarm.sh:fallback_skip, bin/swarm.sh:codex_fallback (header line), bin/swarm.sh:CFG_fallback_reviewer comment, bin/lib/build.sh:codex_rule, bin/lib/build.sh:review_brief (codex limit sentence), tests/codex_rate_limit_test.sh, docs/reference-building.md:codex-review paragraph (§ Building), docs/method.md:fallback_reviewer row (§ Configuring a project), docs/reference-models.md:fallback_reviewer setting and review-fallback role, docs/reference-lead.md:codex-review line (§ The lead), commands/swarm.md:codex-review step, bin/swarm.sh:codex_fallback brief (1039), bin/swarm.sh:review-fallback policy comment (441), docs/reference-logs.md:codex-limit line (862), docs/reference-models.md:fallback sentence (121), bin/lib/reports.sh:header comment (8)]
estimate_lines: 150
easy: false
---

# codex-review treats codex's rate limit as a limit: incident, fallback reviewer, and the Foundry capacity note

On Foundry, codex stopped on an Azure token rate limit (.swarm/reviews/*.md: 'codex skipped: token rate limit (Azure, gpt-6.1-sol)'). CODEX_LIMIT_RE (bin/swarm.sh:935) matches only ChatGPT's usage-limit line: this project's events.tsv has 0 codex-limit incidents in 15,988 lines, so fallback_reviewer = sonnet (.claude/swarm/config) never ran. Add codex's rate-limit line as an anchored, exact pattern beside CODEX_LIMIT_RE. The codex 0.164.0 binary holds 'exceeded retry limit, last status: ' (a 429); confirm the full line in codex's source for that version and quote it in the PR. On a match, codex_review (swarm.sh:908-915) logs `codex-limit: rate limit` and runs the fallback as it does for a usage limit. fallback_skip (942), the fallback header (1000) and the CFG_fallback_reviewer comment (247) name which limit. The brief lines that quote these (build.sh codex_rule 165-170, review_brief 1574-1580) say 'usage or rate limit'. Add a short docs note: a Foundry deployment's token rate limit is its capacity, which the user raises in Azure; the swarm never changes it. No new setting. The real line, captured from three codex runs on 2026-11-01 against Azure Foundry: `ERROR: rate limit exceeded: Your requests to gpt-6.1-sol for gpt-6.1-sol in swedencentral have exceeded token rate limit.` (codex printed it after five `ERROR: Reconnecting... n/5` lines). Match that line; the test's stub prints it verbatim. Keep codex's last 20 lines in the run's incident when a codex run fails, so a future limit message that does not match can be read. 'usage limit' text that becomes false moves too: the fallback agent's brief (bin/swarm.sh:1039), the review-fallback policy comment (:441), docs/reference-logs.md:862, docs/reference-models.md:121 and bin/lib/reports.sh:8.

**Done when:**
- tests/codex_rate_limit_test.sh: a codex stub that prints the captured Foundry line verbatim and exits 1 makes codex-review log a `codex-limit: rate limit` incident and, with fallback_reviewer set (fallback_reviewer_test.sh's stubs), print `reviewed by fallback <model>: codex rate limit`; with the new pattern removed the test goes red.
- Same file: a review that only quotes the rate-limit words (codex exits 0, or the words sit outside the last 5 lines) logs no incident.
- Same file: a failed codex run's incident carries its last lines.
- Same file: the briefs codex_rule and review_brief produce say 'usage or rate limit' where they said 'usage limit'.
- The usage-limit cases in codex_test.sh, fallback_reviewer_test.sh, incidents_test.sh and review_test.sh pass with their text unchanged.
- docs/reference-building.md's codex-review paragraph, docs/method.md's fallback_reviewer row, docs/reference-models.md's fallback lines, docs/reference-lead.md:497 and commands/swarm.md:282 say 'usage or rate limit', and the codex-review paragraph has the Foundry capacity note.

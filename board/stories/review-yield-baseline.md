---
kind: lead
status: blocked
blocked_by: [review-yield-report]
epic: review-yield
depends_on: [review-yield-report]
touches: [board/stories/review-yield-tuning.md (Baseline section)]
---

# The lead posts swarm-dev's findings so far, by kind, as the baseline on review-yield-tuning

Once review-yield-report merges, run the main checkout's bin/swarm.sh review-yield over swarm-dev with no --since. Every row logged before finding-reviewer-column merged reads `unknown`. Add a **Baseline** section to board/stories/review-yield-tuning.md through a board PR: the cut date, totals, and per kind raised, fixed, declined and rate for every kind with 5 or more findings. Correct the epic's rough count (209 declined vs 138 fixed, board/epics/review-yield.md:11): the survey measured 207 vs 140 (59.7%) on 2026-10-15. Note infrafactory's rate (68 of 487 declined, 14%) in one line, so the 60% is read as swarm-dev's. No the lead step.

**Done when:**
- The Baseline section is on main in review-yield-tuning.md, and its fixed and declined totals equal an independent awk count over .swarm/findings.tsv rows dated on or before the cut (NF==4 counts fixed; otherwise field 5); a mismatch means the report or the section is wrong and blocks this story.
- Every kind with 5 or more findings in those rows appears with its counts.

**From review (binding; overrides the scope above where they differ):**
- The lead also adds `--reviewer <who>` to AGENTS.md's log-finding line (AGENTS.md is lead-only).
- The baseline counts what finding_rows keeps (fixed or declined), not raw rows; it notes infrafactory's rate (about 14%) apart from swarm-dev's (about 60%).

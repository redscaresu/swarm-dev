---
kind: lead
status: later
epic: review-yield
after: review-yield
depends_on: [demote-kinds-key, reviewers-deferred-column]
needs: [demote-kinds-key (the demote_kinds key, a comma-separated kind list, deferred on rounds 1 and 2), reviewers-deferred-column (the deferred column the after reading uses)]
touches: []
---

# Lead: switch demote_kinds on for the four declined kinds, then read whether the decline rate fell

Re-filed by review-yield-before (2026-11-15). The user agreed the narrowing: this story carries the
review-yield epic's tuning PR, its after reading and the 4+ round bar.

## Before (v0.30.0 build)

Source: `.swarm/findings.tsv`, rows dated 2026-10-28 to 2026-10-31 (the v0.30.0 build: v0.29.0 was
tagged 2026-10-28T21:38Z, v0.30.0 2026-10-31T17:48Z; the file's dates are whole days, so the window
holds a few rows from either side of the tags). Counted with a one-off script over the file, not a
live `flow` run (AGENTS.md keeps live reports to today). Only fixed and declined rows count. 92 PRs.

| kind | raised | fixed | declined | declined % |
|---|---|---|---|---|
| duplicate-code | 58 | 2 | 56 | 97% |
| missing-case | 44 | 7 | 37 | 84% |
| efficiency | 22 | 1 | 21 | 95% |
| hot-path-cost | 22 | 1 | 21 | 95% |
| all kinds | 1,417 | 467 | 950 | 67% |

The epic quoted missing-case 30 of 32 and hot-path-cost 17 of 18 from an earlier read of the same
build. The table above is the whole window.

review_loops' 4+ round share, from the same rows' round column: 13 of 85 PRs with a numbered review
round reached round 4 or later (15%), against the HLD's 15% bar.

## Steps

1. Once `swarm.sh version` shows a release carrying demote-kinds-key, open a PR adding
   `demote_kinds = duplicate-code,missing-case,efficiency,hot-path-cost` to .claude/swarm/config,
   with the Before table in its body. **You:** merge it: .claude/ is a protected path.
2. After one epic built wholly after that merge, run `gh api rate_limit`, then
   `swarm.sh flow --epic <e>` once. Per kind, record the non-deferred decline rate,
   (declined - deferred) / (raised - deferred), and escaped-of-deferred from the rounds totals. Match
   deferred and escaped rows by PR and exact finding text, filtered to the four kinds:
   review_loops' totals span every kind (flow_review_loops.py:218). Record the 4+ round share against
   the 15% bar.
3. Keep the line if the sent decline rate fell for the four kinds and no deferred finding of those
   kinds proved real. Otherwise open a revert PR. **You:** merge it.

Board PRs that only edit, hold or finish stories get no codex review (commands/swarm.md).

**Done when:**
- The config PR adding `demote_kinds` has merged, linked here.
- The after reading is recorded here, with its epic, window, the per-kind non-deferred decline rate,
  escaped-of-deferred and the 4+ round share, beside the Before table.
- The line is kept, with the reading that justified it, or a merged revert PR is linked with the
  numbers that failed.

**At the v0.31.0 retro (2026-11-17):** kept. Its step 1 can start once v0.31.0 ships demote-kinds-key.

---
kind: lead
status: ready
epic: review-yield
depends_on: [review-yield-baseline]
touches: [board/stories/review-yield-tuning.md, board/stories/<tuning story>.md (new, filed by the lead)]
---

# After one epic's findings with reviewers, the lead tunes the reviewer or kind that gets declined most and checks the decline rate fell

After one epic built wholly on v0.19.0 or later (which carries the reviewer column and review-yield) has merged, run `swarm.sh review-yield --since <that epic's first merge date>` and post it here beside the Baseline. Pick the change it shows. (a) For a (reviewer, kind) declined most, a line naming that kind in finding_rule or the conductor rules, or in the /code-review call: codex takes no prompt (board/stories/codex-bump-not-a-finding.md:12), so the line steers whoever reads its output. (b) Skipping /code-review on docs, chore and board-only PRs: review_rule (bin/swarm.sh:1509) and epic mode (:2062) already say so, so choose (b) only if code-review rows land on such PRs. File each change as its own story (kind code, no epic, so it bumps plugin.json itself) whose body carries the before numbers. After it ships and one more epic merges, run review-yield --since its merge date and record whether the tuned row's rate fell; if not, file a revert story and say so here. No the lead step.

**Done when:**
- The posted report covers every PR of the measured epic with no `unknown` reviewer row for them; if one is unknown, briefs-name-the-reviewer is not being followed, and that is recorded here instead of tuning.
- At least one tuning story is filed, naming the reviewer, the kind(s) and the before raised/declined/rate.
- A later report is recorded here showing the tuned row's decline rate lower than the before number, or a merged revert PR is linked with the numbers that failed.

**From review (binding; overrides the scope above where they differ):**
- The lead runs `claude plugin update` before the measured epic; nothing here waits on the user.
- Done only when the tuning PR has merged (linked), and the before and after reports are `review-yield --epic <e>` for the epic run before and the one run after it, each listing its PR URLs with no `unknown` reviewer rows; the after rate for the tuned reviewer or kind is lower, or the lead reverts the change and says so. It notes that outcomes-every-attempt changed the rounds join between baseline and after.

## Baseline

Cut: 2026-10-16 ~01:00, every row in swarm-dev's `.swarm/findings.tsv` (2026-10-13 to the cut), from `swarm.sh review-yield` with no `--since`. It counts what finding_rows keeps (fixed or declined). An awk count over the same file gives the same totals: 211 fixed, 364 declined.

**Total:** 575 raised, 211 fixed, 364 declined, 63% declined. Reviewers: 487 rows predate finding-reviewer-column and read `unknown` (61% declined). Of the rest, code-review has 84 (75% declined) and codex 4 (3 of them the version bump). Review rounds: 85 over 70 PRs (1.2 per PR, at most 4). The epic's earlier count of 207 declined against 140 fixed (about 60%) was taken on 2026-10-15. infrafactory reads differently, with 68 of 487 declined (14%), so the 63% is swarm-dev's alone.

Every kind with 5 or more findings, across all reviewers:

| kind | raised | fixed | declined | declined % |
|---|---|---|---|---|
| unhandled-state | 96 | 28 | 68 | 71% |
| loose-match | 63 | 22 | 41 | 65% |
| redundant-work | 53 | 4 | 49 | 92% |
| docs-misstate-code | 46 | 27 | 19 | 41% |
| condition-drift | 43 | 20 | 23 | 53% |
| fails-open | 32 | 20 | 12 | 38% |
| fails-silent | 21 | 12 | 9 | 43% |
| view-disagrees | 20 | 7 | 13 | 65% |
| misleading-error | 19 | 9 | 10 | 53% |
| vacuous-test | 19 | 11 | 8 | 42% |
| wiring | 19 | 9 | 10 | 53% |
| stale-read | 15 | 6 | 9 | 60% |
| unhandled-error | 14 | 8 | 6 | 43% |
| release-bump | 12 | 1 | 11 | 92% |
| docs | 12 | 5 | 7 | 58% |
| version-bump | 11 | 0 | 11 | 100% |
| duplicated-source-of-truth | 10 | 2 | 8 | 80% |
| test-leak | 10 | 3 | 7 | 70% |
| scope-creep | 8 | 1 | 7 | 88% |
| lost-coverage | 8 | 2 | 6 | 75% |
| layout-overflow | 6 | 3 | 3 | 50% |
| missing-version-bump | 5 | 0 | 5 | 100% |
| unsanitized-input | 5 | 1 | 4 | 80% |

What it shows before tuning: the three bump kinds (release-bump, version-bump, missing-version-bump: 28 raised, 1 fixed) are already covered by codex-bump-not-a-finding (#171). Of the rest, redundant-work (92% declined), scope-creep (88%) and duplicated-source-of-truth (80%) are the noisiest. unhandled-state is the largest declined count, at 68. The kinds that mostly get fixed are fails-open, docs-misstate-code, vacuous-test and fails-silent, all under 45% declined.

## Codex budget (added 2026-10-16)

Codex hit its usage limit at about 16:00 on 2026-10-16, and every review after that ran without it.
Part of the day's budget went on board PRs; story-adding board passes found real gaps (two on
infrafactory #587, four on a draft sync story), but tidy-ups (deletions, status flips) found
nothing. The user agreed: code PRs come first. Among the tuning stories, file one that runs codex on
a board PR only when it adds or rewrites a story, and never on a PR that only deletes stories or
changes front matter.

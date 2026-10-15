---
kind: lead
status: blocked
blocked_by: [review-yield-release, review-yield-baseline]
epic: review-yield
depends_on: [review-yield-release, review-yield-baseline]
touches: [board/stories/review-yield-tuning.md, board/stories/<tuning story>.md (new, filed by the lead)]
---

# After one epic's findings with reviewers, the lead tunes the reviewer or kind that gets declined most and checks the decline rate fell

After `claude plugin update` installs review-yield-release and one epic built wholly on it has merged, run `swarm.sh review-yield --since <release merge date>` and post it here beside the Baseline. Pick the change it shows. (a) For a (reviewer, kind) declined most, a line naming that kind in finding_rule or the conductor rules, or in the /code-review call: codex takes no prompt (board/stories/codex-bump-not-a-finding.md:12), so the line steers whoever reads its output. (b) Skipping /code-review on docs, chore and board-only PRs: review_rule (bin/swarm.sh:1509) and epic mode (:2062) already say so, so choose (b) only if code-review rows land on such PRs. File each change as its own story (kind code, no epic, so it bumps plugin.json itself) whose body carries the before numbers. After it ships and one more epic merges, run review-yield --since its merge date and record whether the tuned row's rate fell; if not, file a revert story and say so here. No the lead step.

**Done when:**
- The posted report covers every PR of the measured epic with no `unknown` reviewer row for them; if one is unknown, briefs-name-the-reviewer is not being followed, and that is recorded here instead of tuning.
- At least one tuning story is filed, naming the reviewer, the kind(s) and the before raised/declined/rate.
- A later report is recorded here showing the tuned row's decline rate lower than the before number, or a merged revert PR is linked with the numbers that failed.

**From review (binding; overrides the scope above where they differ):**
- The lead runs `claude plugin update` before the measured epic; nothing here waits on the user.
- Done only when the tuning PR has merged (linked), and the before and after reports are `review-yield --epic <e>` for the epic run before and the one run after it, each listing its PR URLs with no `unknown` reviewer rows; the after rate for the tuned reviewer or kind is lower, or the lead reverts the change and says so. It notes that outcomes-every-attempt changed the rounds join between baseline and after.

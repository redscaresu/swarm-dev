---
kind: code
status: blocked
blocked_by: [outcomes-attempt-events, finding-reviewer-column]
epic: training-export
depends_on: [outcomes-attempt-events, finding-reviewer-column]
touches: [bin/swarm.sh:outcomes_report (slug loop, pass 2), tests/outcomes_test.sh]
---

# outcomes adds each row's epic, merged-at, whether the story finally merged, and findings fixed and declined by reviewer

The per-slug shell loop and pass 2 of outcomes_report (bin/swarm.sh:1046-1073). Append, never reorder: epic (front matter `epic:` from story_text, which already reads deleted stories from git), merged_at (mergedAt from the same gh pr list call outcomes-every-attempt leaves, for the row's PR), story_merged (true on every row of a slug when any of its PRs is MERGED, false otherwise, empty when gh failed), findings_declined, findings_fixed_by and findings_declined_by (`<reviewer>:<n>` pairs, sorted, space-separated). Read findings only through finding_rows and the reviewer by its column as finding-reviewer-column defines it (unknown for 4- and 5-field rows), never by row width (:807-814). kind: for a story that now says kind: lead with escalated_from:, report escalated_from (without ` (default)`), so an escalated build keeps its real kind.

**Done when:**
- tests/outcomes_test.sh: a story with `epic: e1` shows e1; one without shows empty; a merged story deleted from the board still shows its epic from git.
- Stub gh returns mergedAt: the merged row shows that time, the closed row empty; a retried slug with #1 CLOSED and #2 MERGED shows story_merged true on both rows; a slug with only a closed PR shows false; with gh failing story_merged is empty.
- Fixture findings on one PR (a 4-field row, a 5-field declined row, a 6-field fixed row with reviewer codex, a 6-field declined row with reviewer code-review) give findings_fixed 2, findings_declined 2, findings_fixed_by `codex:1 unknown:1`, findings_declined_by `code-review:1 unknown:1`.
- A story file saying kind: lead and escalated_from: code reports kind code.
- The first 17 header columns and the columns outcomes-attempt-events added keep their order; tests/decisions_test.sh passes unchanged.
- The PR shows each new check failing with its code removed; shellcheck and every tests/*_test.sh pass.

**From review (binding; overrides the scope above where they differ):**
- story_merged and merged_at are empty (unknown) when the story text is gone, it has no resolvable repo, or gh exits non-zero; false only when gh succeeded with no MERGED PR. Pin each.
- Two attempts naming one PR: each finding goes to the latest attempt on that PR that started on or before the finding's date, so counts never repeat; pin it.
- A `kind: lead` story with `escalated_from: code (default)` reports kind code; `kind: lead` without escalated_from reports lead.
- Updates docs/method.md's outcomes column prose and README's outcomes line for every column outcomes-attempt-events and this story add.

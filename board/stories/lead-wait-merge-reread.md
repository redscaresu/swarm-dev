---
kind: code
status: ready
epic: board-loose-ends
depends_on: []
touches: [bin/lib/lifecycle.sh:lead_wake (merge-triggered heads pass, merged-story drop), bin/lib/lifecycle.sh:lead_merged (new: slugs merged since the last read), tests/wait_lead_test.sh:merge cases (new block), docs/reference-lead.md:merge sentence (§ The lead, after the heads-pass paragraph)]
estimate_lines: 170
easy: false
---

# wait --lead reads a merge at once: a heads pass on the next poll, and no line for a merged story

The board files are already re-read on every poll. What lags after a merge is PR state. #755's case (events.tsv 2026-10-30): `merge doc-anchor-check ok` at 12:08:26, main CI ok at 12:15:19, and wait --lead still printed `no-agent: doc-anchor-check` with a `swarm.sh merge --head` exit at 12:18:47. The story file stays until reconcile, and no_agent_exit (lifecycle.sh:3989-4012) never asks whether the PR merged. Separately, the PR state behind merge:, unmerged: and conflict: lines is read only in a heads pass every LEAD_HEADS_EVERY (300 s; lifecycle.sh:2366, 4478-4485), so those lines can be up to 5 minutes stale after a merge. Change lead_wake in two ways. (1) When events.tsv has a `merge` line newer than the run's last heads pass, run the heads pass on this poll. Read only the bytes added since the last poll, with an offset kept in .swarm/lead/, never the whole file each poll. (2) Before the LEAD_SEEN diff, drop every line whose slug (the word lead_wake logs, lifecycle.sh:4508) names a story with a `merge <slug> ok` event for each PR in its prs:, newer than its last build start. A merged story then names no line, whatever the producer. Exact slug match, no prefix match (rules.md:23). Events and board files only; no new gh call beyond the heads pass a merge triggers. Docs: one sentence in docs/reference-lead.md § The lead. A merge event's target is whatever the caller gave (bin/lib/merge.sh:1152, 1188): a PR URL or a story slug. So a story counts as merged only when each URL on its prs: has a `merge <url> ok` or `merge <url> merged elsewhere` event, or the story slug has one, newer than its last build start; and a PR the heads pass reads as MERGED counts too, which covers a merge the user made on GitHub (merge = human), with no event. One merged PR never hides lines for another PR of the same story that is still open. Correction: a story merge's event names the slug, not the URL given (merge.sh:1024 takes a URL, :1050 logs the slug). So a slug event proves a merge only for a story with one PR on prs:; with two or more, each PR counts as merged only when the heads pass reads it MERGED or a URL event names it.

**Done when:**
- tests/wait_lead_test.sh merge cases, with SWARM_LEAD_HEADS_EVERY=300: a `merge <PR URL> ok` event appended between two polls makes the second poll run a heads pass (the gh stub's open-PR call count goes up by one) and print no unmerged: or conflict: line for that PR. With no merge event, the second poll makes no gh call.
- A story in review whose builder and review panes are gone and that has a `merge <slug> ok` event prints no no-agent: line (the #755 case). The same story with no merge event still prints it.
- A story with two PRs on prs:, one with a `merge <url> ok` event and one still open, keeps its lines for the open one.
- A `merged elsewhere` event, and a PR the heads pass reads as MERGED with no merge event, each drop the line as `ok` does.
- Removing the drop (copy-aside proof) turns the second case red; removing the trigger turns the first red.
- tests/doc_check_test.sh, shellcheck and scripts/select-tests.sh --run pass.
- A story with two PRs and one slug-targeted `merge <slug> ok` event keeps its line for the PR GitHub still reads as open.
- A merge event older than the story's latest build start does not drop its no-agent: line.

---
kind: code
status: blocked
epic: reliable-runs
depends_on: [codex-unavailable-fallback]
needs: [codex-unavailable-fallback (the `codex-unreachable` incident and the `codex <kind>` fallback line it adds; this story reads both)]
touches: [bin/lib/flow_reviewers.py:merged without codex block, tests/review_yield_test.sh:merged-without-codex fixture, docs/reference-logs.md:merged-without-codex paragraph (reviewers section)]
estimate_lines: 110
easy: true
---

# flow's reviewers section lists the story PRs that merged with no codex review

During the 2026-11-12/13 codex outage, 16 story PRs merged while codex could not run, and the lead listed them by hand from the merge times to re-review them. Nothing records which PRs those are.

Needs from codex-unavailable-fallback: the `incident codex-<story> "codex-unreachable"` event and the fallback's `codex <kind>` line, with kind `unreachable` or `timeout`.

Add a `merged without codex` block to `swarm.sh flow`'s reviewers section (bin/lib/flow_reviewers.py). It lists each story PR merged in the window whose every codex-review ended without codex reviewing: a `reap` event `timed out after`, an incident `codex-limit:` or `codex-unreachable`, or a fallback review. Give its slug, PR, merge date and how each round ended (`fallback`, `skipped`). Read only events.tsv and the merged PRs flow already fetches: no new gh call. A PR where at least one round had codex review is not listed.

**Done when:**
- tests/review_yield_test.sh has a fixture with three merged story PRs: one with codex reviewing every round, one with every round timed out, and one with a round that fell back after `codex-unreachable` and then a round codex reviewed. The block lists only the second, with `skipped`
- A fourth PR whose only round fell back after a limit is listed with `fallback`
- An empty window prints the block's heading and `none`
- The listing goes red when the every-round check is changed to any-round, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- No gh call is added: the test's gh stub records its calls, and the count matches the same run without the block
- docs/reference-logs.md's reviewers section has a paragraph naming the block and what it is for: the list to re-review once codex is back
- scripts/select-tests.sh --run passes

---
kind: code
status: ready
epic: merge-mechanics
depends_on: []
touches: [bin/lib/build.sh:story_brief, docs/reference-building.md:Pick the wave, tests/epic_briefs_test.sh:base merge-in case, bin/lib/merge.sh:merge-in refusal texts (501, 552), bin/lib/build.sh:base nudge (140), tests/merge_rules_test.sh:merge-in refusal texts]
estimate_lines: 110
easy: false
---

# Builders merge the base in only on a conflict or when swarm.sh says to

HLD telemetry item 9 (HLD:526-527): 220 behind merge-ins over 63 PRs in the v0.30.0 build, each a CI rerun. Merge time is covered already: base_rounds (bin/lib/merge.sh:624-660) has GitHub merge the base in only when base_moved finds code the head lacks. events.tsv holds 33 `merge ... base-merged` lines over 22 stories between the v0.29.0 and v0.30.0 tags (2026-10-28T21:38Z to 2026-10-31T17:49Z; read once by the scoping run), so most of the 220 were merges agents pushed. The builder brief says to merge origin/<base> on CONFLICTING (story_brief, build.sh:552-553) but never says not to otherwise. Add next to that sentence: merge origin/<base> into your branch only when the PR is CONFLICTING or a swarm.sh line tells you to (a Stacked line, a merge refusal, a nudge); never because the base moved, since swarm.sh merge brings the base in at merge time and each merge-in reruns CI. clash_rule (build.sh:1999-2010) already nudges a merge-in only on a conflict: leave it. Prompt text: assert it positively in tests/epic_briefs_test.sh, which reads a rendered .swarm/briefs/<slug>.md (151). merge's own refusals also ask for a merge-in with no conflict (merge.sh:501, 552: 'merge origin/<base> in, push, and merge the new head'), and so does the nudge at build.sh:140. Change each so it asks for a merge-in only where the merge cannot go ahead without one, and says why; where swarm.sh merge brings the base in itself, say that instead. The PR body records `swarm.sh flow`'s merge_ins block (conflict and clean-while-behind counts) for the v0.30.0 window, so the checkpoint can compare.

**Done when:**
- tests/epic_briefs_test.sh: a rendered builder brief holds the new sentence (exact text), and the case goes red with the sentence removed (PR body).
- docs/reference-building.md § Pick the wave says a builder merges the base in only on a conflict or when a swarm.sh line says to.
- The PR body lists each line in bin/lib/build.sh that tells a builder to merge the base in, and the condition each names.
- tests/merge_rules_test.sh: each of merge's merge-in refusals pins its new text, which names the condition that needs the merge-in.
- The PR body has flow's merge_ins block for 2026-10-28 to 2026-10-31.

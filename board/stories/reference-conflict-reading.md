---
kind: code
status: ready
epic: reference-split
depends_on: []
touches: [docs/features.tsv:reference split row (new)]
estimate_lines: 2
easy: true
---

# Record where the v0.29.0 window's conflict merge-ins fell in docs/reference.md, and add the Goal 10 features row

Re-merge the merge-ins of the PRs squashed into main in v0.28.0..v0.29.0 (121 first-parent commits, 78 touching docs/reference.md) the way bin/lib/flow_merge_ins.py:78-105 does. In a scratch clone under the build's temp dir, fetch those PRs' refs/pull/<n>/head in one fetch. Take each merge commit whose second parent is on main, re-run git merge-tree on its parents, and map each docs/reference.md conflict hunk to the ## section that holds it on that base. Count as flow_merge_ins.py does: a merge whose merge-tree is clean but whose committed docs/reference.md differs from the clean result is a hand-resolved conflict, mapped by the sections its committed change touches. No gh REST loop and no flow run over the window: AGENTS.md allows flow only once, with --since today. The script and its table go in the PR body, not the repo; delete the scratch clone after. Add the docs/features.tsv row for Goal 10: feature `reference split`, landed `reference-split`, metric `flow merge_ins: conflict merge-ins whose files include a docs/reference*.md file, over all conflict merge-ins`, saying the file-conflicts block lists only the top three files, per file (bin/lib/flow_merge_ins.py:151-152); baseline `92 of 194 conflict merge-ins (47%), v0.29.0 build (HLD 2026-10-28 Problem 7); bar under 10%`; uses `unlogged: a read-only reading`.

**Done when:**
- The PR body's first line is the verdict, chosen from the measured distribution: `split inside <section>` when one ## section holds over half of the docs/reference.md conflict merge-ins, else `split by group`. The line names the sections and their counts that justify it.
- The PR body has a table of conflict merge-ins and conflict hunks per ## section, with its denominators: merge-ins read, merge-ins with a docs/reference.md conflict, PRs, and each unread merge-in named with its reason.
- docs/features.tsv has exactly one `reference split` row, with landed `reference-split`, the 92 of 194 baseline and the under-10% bar, and scripts/select-tests.sh --run passes with tests/features_test.sh in its run.
- The PR's diff is docs/features.tsv only.

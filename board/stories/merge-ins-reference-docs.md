---
kind: code
status: ready
epic: doc-hotspot
depends_on: []
touches: [bin/lib/flow_merge_ins.py:tally (reference_docs count), bin/lib/flow_merge_ins.py:cause table print (reference_docs column), tests/flow_test.sh:merge_ins cases, docs/reference-logs.md:merge_ins paragraph (§ Flow and features), docs/features.tsv:doc hotspot row (new, after reference split), docs/features.tsv:reference split row, tests/features_test.sh:EXEMPT and the reference split exemption check, bin/lib/reports.sh:merge_ins header comment (385)]
estimate_lines: 70
easy: true
---

# flow merge_ins counts conflict merge-ins on docs/reference*.md, and features.tsv reads it

No depends_on. The features row the epic asks for needs a count that no flow output gives: merge_ins prints only the three files conflicts hit most, per file (bin/lib/flow_merge_ins.py:151-153), and tests/features_test.sh exempts the reference split row for that reason (:139-143, :198). In flow_merge_ins.py, count each conflict merge-in once when its conflicted files (what tally gets, :119) include docs/reference.md or a docs/reference-*.md, and print the count as a fourth column `reference_docs` of the cause table (:148-150): the count on the conflict row, `-` on behind, neither and unread, which read no files. A 0 then means no conflict touched those files. The pattern is swarm-dev's own doc layout; another project reads 0. Name the column, its 0 and its `-` in the merge_ins paragraph (docs/reference-logs.md:413-434). In tests/flow_test.sh's merge_ins cases (:163-270), update the pinned headers and add a case: two conflict merge-ins, one on docs/reference-logs.md and one on a code file, print 1. In docs/features.tsv add a row right after `reference split` (:68), not at the end where every features story appends: feature `doc hotspot`, landed `doc-hotspot`, metric `flow merge_ins: reference_docs on the conflict row, over that row's merge_ins`, baseline `47 of 62 conflict merge-ins (76%), 2026-10-30 13:57 UTC (the split, #759) to 2026-11-01, by a git merge-tree replay of the merge-ins on the lead's clone's story branches (doc-hotspot plan); bar under 10%`, uses `unlogged: a read-only reading`. Point the reference split row's metric at the same column, and drop it from EXEMPT (:143) and the check at :198. Never run flow against the real repo; the fixtures show it. The row's baseline (47 of 62) came from a merge-tree replay of local branches, not from flow: say so in the row. bin/lib/reports.sh:385 describes the merge_ins header and changes with it.

**Done when:**
- tests/flow_test.sh: the merge_ins cause header is `cause merge_ins prs reference_docs`; the new case prints 1 on the conflict row and `-` on the other three rows.
- With the path pattern changed to one no path matches (copy-aside proof), the new case goes red, quoted in the PR.
- tests/features_test.sh passes with `reference split` out of EXEMPT, and section_check reports nothing for the `doc hotspot` and `reference split` rows.
- docs/features.tsv's new row sits right after `reference split`; the merge_ins paragraph names `reference_docs`, its 0 and its `-`.
- scripts/select-tests.sh --run passes; shellcheck and `python3 -m py_compile bin/lib/flow_merge_ins.py` are clean.
- bin/lib/reports.sh's merge_ins comment names the reference_docs column, and the features row says its baseline came from a merge-tree replay.
- A fixture where one merge-in conflicts on two reference docs, and two matching merge-ins belong to one PR, counts one per merge-in.

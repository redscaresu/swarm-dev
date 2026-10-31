---
status: draft
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.31.0
depends_on: []
---

# doc-hotspot

docs/reference-logs.md stops being the place every story collides

HLD § v0.31.0 additions. Within a day of the reference split, docs/reference-logs.md caused 66 of 168 conflict merge-ins in the v0.30.0 build, more than docs/reference.md's 44.

**Done when:**
- stage: v0.31.0
- The plan reads where those conflicts fell (by section) and removes the cause: one doc fragment per feature, or the hot section split, or planning treats the file's hot part as a clash part.
- docs/features.tsv row: conflict merge-ins on docs/reference*.md per build, against the reference split's under-10% bar.

**Out of scope:**
Rewriting the reference's content.

**Constraints:**
- stage: v0.31.0. From the HLD's v0.31.0 additions (decided 2026-10-31); /plan-epic scopes it.

**Areas:** docs/reference-logs.md, docs/reference.md (index), bin/lib/touches_rows.py if clash parts change

**Your part:**
- none

---
status: active
parent: less-noise
hld: 2026-10-25-swarm-dev-0-28
stage: v0.29.0
depends_on: []
---

# One helper each for the contents reader, the name cut and the board root; reconcile finishes pulled stories

The duplicated pieces become one helper each, and reconcile finishes a merged story whose file a pull removed.

A child of less-noise, split at planning (2026-10-26). Its stories were planned with the parent; the parent's Out of scope, Constraints and Your part apply.

**Done when:**
- contents-reader: One reader for a file at a PR's ref, for merge_read, pr_hld and release_check
- name-cut-helper: One helper for herdr's 32-character name cut, matching only exact records
- reconcile-pulled-finish: reconcile finishes a merged story whose file a pull already removed
- board-root-helper: One helper for the board's path in the repo, replacing 15 inline copies

**Areas:** see each story's touches.

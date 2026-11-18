---
kind: code
status: later
depends_on: []
touches: [bin/lib/board.sh:newest_tag]
---

# Read tags from origin, as the release gate does

From the v0.31.0 retro (2026-11-17). newest_tag (bin/lib/board.sh:1843) reads local tags while the release gate reads origin's, so next can offer a patch the gate refuses (#974) and a local-only tag counts (#745).

Read tags from origin, as the release gate does.

**Done when:**
- a fixture with a local-only newer tag makes next ignore it; with the change removed next counts it (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

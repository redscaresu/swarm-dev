---
kind: code
status: later
depends_on: []
touches: [bin/lib/board.sh:next conductor start]
---

# next starts a conductor for an active epic with a ready or in-review story and no running conductor

From the v0.31.0 retro (2026-11-17). Twice next started no conductor for an epic with work while its conductor was gone (incidents 774, 784; reliable-runs on 2026-11-16).

next starts a conductor for an active epic with a ready or in-review story and no running conductor.

**Done when:**
- a fixture epic with a green unreviewed PR and no conductor gets one started; with the change removed none (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

**Folded into the v0.32 Python rewrite (the user, 2026-11-18):** not built in bash. The v0.32 HLD names this as a requirement of the command it ports, with this story's Done when as the test the Python version must pass; this file goes when that plan absorbs it.

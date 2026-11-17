---
kind: code
status: later
depends_on: []
touches: [bin/lib/reports.sh:retro window day]
---

# Take the window's first day in the same local time the findings rows use

From the v0.31.0 retro (2026-11-17). retro's window starts from the tag commit's day in the committer's timezone (bin/lib/reports.sh:577) while findings carry local dates, so the window can be a day off (#901, #903, #908).

Take the window's first day in the same local time the findings rows use.

**Done when:**
- a fixture tag committed late UTC on one day and a finding dated the next local day is counted; with the change removed it is not (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

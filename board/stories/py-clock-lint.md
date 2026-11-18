---
kind: code
fix: true
status: ready
depends_on: []
touches: [scripts/lint:python clock]
---

# A lint for date.today()/datetime.now() in bin/lib/*.py outside the clock helper, and dash_slow.py fixed

From the v0.31.0 retro (2026-11-17). bin/lib/dash_slow.py:114 calls the real date.today(), so SWARM_DASH_NOW cannot pin dash's CI day (#854, #586).

A lint for date.today()/datetime.now() in bin/lib/*.py outside the clock helper, and dash_slow.py fixed.

**Done when:**
- make check fails on a fixture .py calling date.today(); dash_slow.py honours SWARM_DASH_NOW (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

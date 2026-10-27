---
kind: code
status: ready
epic: fixes-027
depends_on: []
touches: [tests/dash_stalls_test.sh:fixture clocks, bin/lib/dash_render.py:NOW and TODAY]
estimate_lines: 50
easy: true
---

# dash_stalls_test passes at 00:30 BST

tests/dash_stalls_test.sh fails locally between 00:00 and 01:00 BST and passes under TZ=UTC (HLD Appendix C, board/hld/2026-10-25-swarm-dev-0-28.md:872). It mixes clocks: `date +%F` (:72, :250) and `touch -t` from local time (:163-164), against ago()'s UTC events (:90), while dash_render's TODAY is local (bin/lib/dash_render.py:11-12). Run the test at one fixed instant, 2026-07-16 00:30 BST (2026-07-15T23:30:00Z), with TZ=Europe/London. Fix SWARM_DASH_NOW to that instant and derive every fixture time from it, not from the real clock. If dash itself reads a clock SWARM_DASH_NOW does not fix, fix dash and say so in the PR.

**Done when:**
- At 00:30 BST, on the real clock or a faked one, the test as it is on the base fails; the PR cites the run and how the clock was faked.
- After the fix the test runs at the fixed instant on any machine and passes, under TZ=Europe/London and under TZ=UTC.

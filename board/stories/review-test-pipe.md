---
kind: code
status: ready
epic: fixes-027
depends_on: []
touches: [tests/review_test.sh:watch stub]
estimate_lines: 40
easy: true
---

# review_test's watch test stops dying on Broken pipe

The watch test in tests/review_test.sh (:585-596) sometimes dies on 'Broken pipe' on stdout, then passes on a rerun. Name the writer first, from a failing run's own output line. The stub's pr list already writes once (:53-56), and watch_prs reads its rows from a here-string (bin/lib/merge.sh:1555-1598), so watch itself closes no pipe early. The likely writers are the stub's direct writes: `jq ... | jq -r` in the pulls/<n> case (:64-65) and `cat` in the check-runs cases (:66 onwards). Force that exact writer on that watch path to hit a closed reader, so the watch check fails every time before the fix and passes after. Fix it the way the pr list case was fixed, or at its cause.

**Done when:**
- The PR names the writer, quoting the failing line.
- The forced reproduction of that writer on the watch path fails on the base and passes after; the PR cites both runs.

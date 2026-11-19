---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [go-layers, binary-fetch, release-client, port-inventory, port-checks]
stage: v0.32.0
---

# One Python helper is replaced by the Go binary end to end by the six port steps, so the method is proven once before the other helpers use it

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** The chosen helper's .py file is gone and the bash calls the binary for it. Its tests pass with no file under tests/ changed but the ones its story lists. The differential run against the tree just before the port is clean. The harness shows the command starts no python3 for that helper. The mutation proofs are repeated against the Go. No doc names the deleted file. On an installed-copy fixture with no binary variable set, a command with no marker that calls the helper gets the binary and runs. On a fixture of this history the widened patch gate passes the port PR as a `port: true` story.

**Out of scope:**
- The other 59 helpers
- The release and the stage exit (foundation-exit)
- Any behaviour change

**Constraints:**
- stage: v0.32.0, so v0.32.0 waits for it (bin/lib/board.sh:1438-1453).
- The freeze starts when this epic's first story starts (HLD:343). From then main takes only port stories, their test rewrites, fix: true stories and fix-main builds.
- Pick a helper under the 300-line story cap that the bash runs as a process, that imports no shared module (contradiction 1), that no other helper imports (contradiction 24), that no inline `python3 -c` site imports (contradiction 2), and that is not ci_gate.py, which CI's gate runs (contradiction 4).
- It sets the pattern each later helper port follows: how bash names the binary's helper entry, where the Go package sits, and what the port PR records.
- Tests-only PR first, port PR second (HLD:250-262).
- py_compile, LINT_FILES and the test map still pass with one file fewer (.github/workflows/ci.yml:44; Makefile:47; scripts/test-map.tsv).

**Your part:**
- Before its first story starts, you finish or close the 8 active epics and clear or drop the 6 ready lead stories (HLD:343-345): status-speed-readings, reliable-runs-readings, flaky-tests-readings, doc-hotspot-reading, ppid-check-after-review, review-follows-live-check.
- You also call the three stories that keep epics open: effort-trial (blocked), release-confirm-answer (blocked), review-yield-tuning (later). And PRs #547 and #557.
- Lead: check that the dropped-lines fix has merged before the freeze starts (story dropped-lines-own-story-file, in bash, outside this plan; HLD:76-78).
- status-speed-readings times `status` in bash before status is ported (open question 2).
- Lead: hold the freeze in every plan from here on.
- Carve-out (HLD:480-485): none. The port story sets port:, which no longer puts a story on the list.

**Areas:**
- internal/ (the first helper's package)
- cmd/
- bin/lib/<helper>.py (deleted)
- bin/lib/*.sh (its call sites)
- tests/ (listed files)
- docs/

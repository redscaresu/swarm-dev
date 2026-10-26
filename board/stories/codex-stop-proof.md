---
kind: lead
status: blocked
epic: test-speed
depends_on: [codex-runs-no-tests]
needs: [codex-runs-no-tests: the merged refusal in scripts/test.sh or the read-only flag in bin/swarm.sh:codex_review]
touches: []
estimate_lines: 0
easy: true
---

# Lead: a real codex review under the merged stop starts no test file

Needs codex-runs-no-tests' merged stop (scripts/test.sh's refusal or codex_review's read-only flag) on main. In a fresh stub repo built as codex-review-probe built it, but with main's current scripts/test.sh and Makefile, the lead runs one real review: route (b) through main's `bin/swarm.sh codex-review main`, route (a) as `codex exec review --base origin/main`. The prompt asks codex to run `make test`. The lead records codex's output, the probe token's absence, and `ps -axo pid,ppid,command | grep probe_test` during and after. A token or a probe process means the stop failed: the story goes back to codex-runs-no-tests.

**Result (lead, 2026-10-26 03:4x, codex-cli 0.164.0, a stub repo holding main's scripts/test.sh and Makefile after codex-runs-no-tests merged, and a tests/probe_test.sh that touches a marker file and runs `sleep 30`):**
- `codex exec 'Run exactly this shell command and print its full output: make test'`: codex ran it and got `test.sh: refused under codex (CODEX_SANDBOX is set): the suite does not run in a codex session; run make test outside codex`, then `make: *** [test] Error 1`.
- `codex exec review --base origin/main`, as codex_review runs it: no test started.
- Across both runs the marker file was never written, and ps (sampled every 3 s, and after) showed no probe_test process.

**Done when:**
- This story's PR or note records one real review under the merged stop in which the probe token is absent from codex's output and ps shows no probe_test process, during the review or after it.

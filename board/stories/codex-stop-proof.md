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

**Done when:**
- This story's PR or note records one real review under the merged stop in which the probe token is absent from codex's output and ps shows no probe_test process, during the review or after it.

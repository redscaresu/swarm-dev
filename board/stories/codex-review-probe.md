---
kind: lead
status: ready
epic: test-speed
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# Lead: record what a real codex 0.164 review sets and runs, in a stub repo

Every real codex call in this epic is the lead's: a builder makes none on the user's login. The lead makes a throwaway stub git repo (mktemp; a local bare remote so origin/main exists). It holds main's scripts/test.sh and Makefile, and a tests/probe_test.sh that prints a unique token and runs `sleep 30` with a unique argument. No real project is touched. Two real `codex exec review --base origin/main` runs (codex --version 0.164.x), each with a prompt asking codex to print the names of the CODEX_* variables in its shell and to run `make test`: (1) as codex_review runs it today (bin/swarm.sh:700, no flag); (2) with `-c sandbox_mode=read-only`. For each run, record: the CODEX_* names and their non-secret values; whether the token appears in codex's output; and `ps -axo pid,ppid,command | grep probe_test` during and after the run. The lead writes the results into codex-runs-no-tests' story file in a board PR, which picks the route.

Review fix (skeptic): also record the CODEX_* names in the lead's own shell and in a builder pane, so codex-runs-no-tests can pick a name codex sets that those two lack.

**Done when:**
- codex-runs-no-tests' story file on main holds, for both runs, the CODEX_* variable names (or none), whether the probe token appeared, and the ps output, with the codex version.

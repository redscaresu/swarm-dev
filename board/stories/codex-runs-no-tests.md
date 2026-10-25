---
kind: code
status: blocked
epic: test-speed
depends_on: [codex-review-probe]
needs: [codex-review-probe: the CODEX_* variable and read-only results it writes into this story file, which pick route (a) or (b)]
touches: [scripts/test.sh:codex refusal, Makefile:test recipe, bin/swarm.sh:codex_review, tests/codex_test.sh:exec args, tests/test_refusal_test.sh, docs/reference.md:codex-review section, README.md:codex line]
estimate_lines: 70
easy: true
risk: high
---

# codex cannot run the suite during a review

Needs codex-review-probe's recorded results in this story file: the variable a real codex 0.164 review sets, and whether `-c sandbox_mode=read-only` stopped the probe test. A safety path: codex-review runs in every project. The builder makes no real codex call; tests use a stub codex (tests/codex_test.sh) and stub test files. Route (a), if the probe recorded a non-SWARM_ variable (scripts/test.sh:34 unsets SWARM_*) in run (1): scripts/test.sh refuses before anything else, and so does the Makefile `test` recipe. The refusal is one line and a non-zero exit, before any mark, log line or job (scripts/test.sh:132-165). Route (b), if the probe showed the flag stopped the test: codex_review passes `-c sandbox_mode=read-only` to `codex exec review` (bin/swarm.sh:700; exec review takes no -s), and reference.md's codex-review section (:832-866) says codex reviews read-only. If the probe showed neither, the story goes back to the lead. herdr's codex agents already run -s read-only or workspace-write (bin/lib/agents.sh:541-543), and no codex builder exists, so (a) blocks no builder. README.md gets the user-visible line in this PR: route (a) in More, route (b) in Cost and safety. A direct `bash tests/x_test.sh` under codex is out of scope. codex-stop-proof proves it on a real review after merge.

Review fixes (skeptic): key the refusal only on a variable codex itself sets that the lead's shell and a builder pane lack, never CODEX_HOME (it is in AGENT_ENV, bin/lib/agents.sh:231, so every builder has it when the user sets it). The refusal comes before log_run (scripts/test.sh:162). Drop the Makefile line, since its recipe only runs scripts/test.sh (Makefile:26-27) and its test could not fail, unless a stub scripts/test.sh that writes a marker proves the Makefile line refuses first.

**Done when:**
- Route (a): tests/test_refusal_test.sh runs scripts/test.sh and `make test` over a stub test that writes a marker, with the recorded variable set; both exit non-zero, print the refusal, write no `run` line and no test-runs.tsv line, and the marker is absent; with the variable unset the stub runs. Route (b): tests/codex_test.sh pins the args `exec review -c sandbox_mode=read-only --base origin/main` and the same flag in the story-prompt form (tests/codex_test.sh:203,216).
- tests/codex_test.sh's passthrough and limit-kill cases still pass, and the PR quotes the probe's recorded results from this story file.
- tests/test_refusal_test.sh asserts the chosen variable is not in AGENT_ENV.
- With TEST_RUNS_LOG set to a temp file and the variable set, the file stays empty and test-runs.d gets no mark; with the variable unset, the same file gets the start and end lines (a positive control).

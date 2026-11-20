---
kind: docs
status: ready
epic: port-inventory
depends_on: []
touches: [docs/port/exit-codes.tsv]
estimate_lines: 260
---

# docs/port/exit-codes.tsv lists each command's, hook's and the gh shim's exit codes on its own path, with the test that pins each

Needs no other story.
- Write docs/port/exit-codes.tsv (`#` header: command, code, when, returned by, pinned by). Cover every arm of bin/swarm.sh's dispatch and early case, each hook script in hooks/hooks.json, and bin/gh-shim/gh.
- For each arm, one row per code on its own path: every literal `exit N` and `return N` with N nonzero in the arm's case body and in the function it calls; each named code by its value with its name (STEP_UP_BUSY=5, bin/lib/lifecycle.sh:746); `die` as 1; every code AGENTS.md or docs/ states for it (wait's 0, 1 and 143; wait-pr's 0, 1 and 2: check them against the code); and 0. Codes passed up from deeper callees are not listed: they cannot be listed in full. The header says so. For a hook, its own literal exits. For the gh shim, that gh's own code passes through.
- when: one short line. returned by: file:function.
- pinned by: the tests/*_test.sh that asserts the code, or `none`. Write no new test: port-checks' differential run compares exit codes (port-checks.md Done when (1)).
- The PR quotes the script that lists, per arm, the codes the rule above finds, and its empty diff against the rows. A command with any such code and only a 0 row fails that diff. It also lists the commands whose nonzero codes no test pins.
- Humanizer over the when column and the PR body.

**Done when:**
- Every arm, hook script and the gh shim at the base has rows. Every code the stated rule finds on an arm's own path has a row naming its file:function and its test or `none`. The PR's diff between the rule's listing and the rows is empty.
- scripts/select-tests.sh --run passes

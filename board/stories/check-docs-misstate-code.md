---
kind: code
status: ready
checks: docs-misstate-code
depends_on: []
touches: [bin/lib/build.sh:review_checklist, tests/review_checklist_test.sh]
estimate_lines: 40
easy: true
---

# The review checks every comment and doc line the diff's behaviour change touches

`docs-misstate-code` recurs in 54 PRs in 30 days, with no check (`swarm.sh outcomes`, 2026-10-23). Recent instances: a function header named rulesets only; the GONE comment contradicted the subscribe path; report.py said 'not JSON' whatever the parse error was; README and reference.md missed a new refusal.

Add one line to review_checklist (bin/lib/build.sh:703), which the review agent and the fallback reviewer read: for every function, flag or message the diff changes, re-read its header comment, its error text and the README/docs/reference.md lines that name it, and a sentence that no longer matches the code is a finding.

**Done when:**
- A test checks that review_checklist's output holds the line, and that the review brief (`review_brief`) includes it.
- `make test` passes.

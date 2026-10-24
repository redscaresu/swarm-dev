---
kind: code
status: ready
depends_on: []
touches: [bin/lib/agents.sh:findings_told, tests/escalate_ladder_test.sh]
estimate_lines: 30
easy: true
---

# The ladder counts every findings round herdr delivered

`findings_told` (bin/lib/agents.sh:1544) counts only `tell:findings` events whose outcome is `ok`. On 2026-10-24, plan-hld-command's three findings tells (07:52, 08:34, 09:21) each logged "the brief was not taken up: herdr sent it the brief twice". The builder did act on each round, so the count stayed at 0 and the ladder never stepped it up through four rounds. The lead had to tell its conductor to run `step-up` by hand.

- `findings_told` also counts a `tell:findings` event whose outcome says herdr sent the brief: "the brief was not taken up: herdr sent it ..." and "it may or may not have the brief: herdr sent it ...". It does not count one where herdr sent nothing, such as "herdr did not send it the brief" or "could not reach".

**Done when:**
- tests/escalate_ladder_test.sh: with two `ok` tells and one "not taken up: herdr sent it the brief twice" tell since the build started, the next findings tell steps the build up. With two `ok` tells and one "herdr did not send it the brief", it does not.
- `make test` passes.

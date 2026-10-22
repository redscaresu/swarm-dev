---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/merge.sh:ci_gate, bin/lib/merge.sh:fix_main, tests/merge_test.sh]
easy: false
estimate_lines: 150
---

# merge judges main by its required checks, and reruns a failed shard once before it writes a fix-main story

On 2026-10-22, `swarm.sh merge` called main red six times, and wrote a fix-main story each time. None of them was a real break:
- Four were known flaky tests (codex_test, wait_pr_test). Each went green when its shard was rerun.
- One was Scorecard, which isn't a required check, failing to start during a GitHub outage.
- One was a timeout on a test-shard GitHub still listed as running after the required `test` check had already passed.

The lead reran each by hand and moved each fix-main story aside.

After a merge, judge main's CI by the base branch's required checks: read the branch protection or rulesets once, and fall back to every check when they can't be read. Report a red non-required check as a warning, never as red main. Once every required check has finished, stop waiting on other checks. When a required check fails, rerun its failed jobs once (`gh run rerun --failed`) and wait again. Only a second red writes the fix-main story, and the story says the rerun also failed. A rerun that goes green prints `flaky: <job> (<FAIL lines>), green on rerun`, and logs it to events.tsv as a flake, so flow-flaky-tests can count it.

**Done when:**
- tests/merge_test.sh, with stub gh: a red non-required check leaves main green with a warning. A required check that's red once and green after its rerun writes no fix-main and logs a flake. One red twice writes fix-main, saying so. A non-required check still in progress after the required ones pass doesn't hold the merge.

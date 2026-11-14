---
kind: code
status: ready
depends_on: []
touches: [bin/lib/agents.sh:bg_running non-test task cap, tests/bg_running_test.sh (new), docs/reference-building.md:stall paragraph (§ Building)]
estimate_lines: 100
easy: true
---

# A background task that is not a test run stops counting as life after a bound

On 2026-11-13/14 the review agent of retro-recurring-extract (#891) hung for 17.5 hours, and nothing reported a stall. A line in its background shell, `$=x 2>/dev/null`, is only a redirect, so zsh ran `cat` (NULLCMD), which waited forever on a socket. bg_running (bin/lib/agents.sh:1375 onward) counts any running background task as a sign of life. Only a test run has a limit: one launched TEST_RUN_STALLS times `stall_minutes` ago or more stops counting (:33, :55, :1378). Any other background task counts as alive however long it runs. So the agent never read as stalled, and the lead found it by hand.

Give a background task that is not a test run the same kind of bound: once it was launched `stall_minutes` × TEST_RUN_STALLS ago or more, it no longer counts as life, so the agent reads as stalled by the usual rules. Test runs keep today's rule. A task still printing output stays alive under the existing rules: this bound only applies to the launch-age test.

**Done when:**
- tests/bg_running_test.sh: a fixture transcript with a non-test background task launched past the bound makes bg_running fail (not alive); the same task launched inside the bound makes it succeed
- A test-run task past the same age keeps today's result, as TEST_RUN_STALLS sets it
- The past-bound case goes red with the new bound removed, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- docs/reference-building.md's stall paragraph says a non-test background task stops counting as life after the bound, and names the #891 hang as why
- scripts/select-tests.sh --run passes

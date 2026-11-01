---
kind: code
status: ready
epic: flaky-tests
depends_on: []
touches: [tests/events_test.sh:term_pid, tests/tell_queue_test.sh:findings told at once while a queued one's delivery is sending (:236-246)]
estimate_lines: 70
easy: true
---

# events_test and tell_queue_test wait on what they check, not a fixed sleep

Needs no other story. Causes, from gh run view <id> --repo redscaresu/swarm-dev --attempt 1 --log-failed. events_test 'a TERM leaves no temp file' (:150, run 40609784108): term_pid sends TERM after a fixed `sleep 2` (:141). live_logs_test failed in the same run only because events_test failed inside it: one cause. tell_queue_test 'its check stays stamped live' (:242-243, run 41218365899): a fixed `sleep 2.5` at :241, where until_ok (:59) exists. Each fix waits on the condition its check reads, bounded. A poll interval inside such a loop is allowed; a fixed sleep before a check is not. Keep live_logs_test green: it runs events_test in a copy. Run the 20 runs one file at a time, JOBS=1.

**Done when:**
- In the PR, both runs are named with their failing check and cause, quoted from the log.
- tests/events_test.sh:141 and tests/tell_queue_test.sh:241 have no fixed sleep before their checks. Each waits, bounded, on what its check reads.
- Forced-delay proof in a worktree copy without .git: the command under test is slowed past the old sleep (the slow/ stub in events_test, the prompt delay in tell_queue_test). The old code fails and the new code passes. The PR quotes both.
- 20 runs each of make test TESTS=<file> JOBS=1, one file at a time, for events_test, tell_queue_test and live_logs_test, all green. The counts are in the PR.
- shellcheck is clean on the touched files.

---
kind: code
status: ready
epic: reliable-runs
depends_on: []
touches: [bin/lib/poll_cache.py, bin/lib/ci_gate.py:pages, bin/lib/merge.sh:wait_pr, tests/wait_pr_cache_test.sh, docs/reference-merging.md:wait-pr row (§ Commands), docs/reference-logs.md:.swarm/poll-cache/ entry]
estimate_lines: 230
easy: false
---

# Concurrent wait-pr runs on one head share each poll's GitHub reads

wait_pr (bin/lib/merge.sh:2158) runs `ci_gate.py head` every MERGE_POLL (20 s) per waiter, and head mode reads check-runs, commit status and actions/runs through pages() (ci_gate.py:45, 65-67, 634-637). Builder, review agent and lead each read the same head; nothing is shared. In this project's gh-calls.tsv (2026-10-30T11:50Z to 2026-11-01T00:45Z) wait-pr made 18,217 of 40,197 REST calls. Add bin/lib/poll_cache.py: one entry per API path (the path holds the full head sha) under ${PROJECT_DIR}/.swarm/poll-cache/, written by temp file + os.replace (gh_cache.py's pattern; macOS has no flock), only after a read pages() accepted; the reader passes its max age; old files are pruned. pages() uses it only when the call sets SWARM_POLL_CACHE (dir) and SWARM_POLL_CACHE_SECONDS (under one poll, so a lone waiter never reads its own entry; 0 is off). wait_pr sets both on its ci_gate call alone, never exported. Merge's CI gates and review-agent --recheck (build.sh:1041) do not, and read GitHub every time. The head read, deadlines, retries, rate-limit waits and --head pinning are unchanged. No config key. Concurrent misses: fetch single-flight per key (a lock file per key, a bounded wait for it, and recovery when the fetcher exited without writing), so two waiters that miss together make one read. The key is the full command form (argv and output filter), not the API path alone, so watch-poll-cache's `-q` output and ci_gate's reads of the same path never read each other's entries. Add .swarm/poll-cache/ to docs/reference-logs.md beside .swarm/gh-cache/ (:325). ci_gate reads Actions runs only with expected-workflow arguments on a non-red head (ci_gate.py:655, 851); the three-read tests pass those arguments. An exit-zero response that pages() rejects (ci_gate.py:45) is a failed read and is never cached.

**Done when:**
- tests/wait_pr_cache_test.sh: two wait-pr runs started together on one PR head, with a stub gh that logs every call and a short poll, log one check-runs, one status and one actions/runs read per poll between them; the same run with the cache off logs two of each; with the cache lookup removed the test goes red.
- Same file: two waiters that start cold together, held at a barrier in the gh stub, make one read per endpoint between them; a fetcher killed before it writes leaves the other to read within one poll.
- Same file: when the stub fails one waiter's check-runs read, no entry is written and the other waiter makes its own read.
- Same file: a wait-pr on a new head of the same PR reads GitHub for that head, and a pending-to-green flip in the fixtures is printed green within one poll.
- Same file: `ci_gate.py head` with expected-workflow arguments, on a non-red head, run without SWARM_POLL_CACHE makes all three reads while a fresh entry for that head is on disk.
- wait_pr_test.sh, wait_pr_expected_test.sh, wait_pr_new_head_test.sh and merge_base_update_wait_test.sh pass unchanged.
- docs/reference-merging.md's wait-pr row says concurrent waits on one head share each poll's reads, kept for under one poll in .swarm/poll-cache/.
- An exit-zero malformed or incomplete response leaves no cache entry, and the other waiter reads successfully.

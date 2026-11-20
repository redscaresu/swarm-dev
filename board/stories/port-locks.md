---
kind: code
status: ready
epic: port-inventory
depends_on: []
touches: [docs/port/locks.tsv, tests/port_locks_test.sh]
estimate_lines: 240
---

# docs/port/locks.tsv lists every lock file with its protocol and each place that takes it, and a test fails on a lock or a taker it lacks

Needs no other story.
- Write docs/port/locks.tsv (`#` header: lock, protocol, stale, file, function, expr, n). One row per take site: a function that takes a lock, keyed by file, function and the lock path as written there (expr, whitespace collapsed), never by line. n is how many times that function takes that expr. lock is the path pattern: `<state>.lock`, `.swarm/reconcile.lock`, `merge-<owner>-<repo>-<base>.lock`, `<pid file>.reclaim` and the rest. The header gives the number of distinct lock files, which is the count the epic asks for (contradiction 9).
- protocol, as the code has it today:
  - perl mkdir(2) (bin/lib/board.sh:3105-3111);
  - plain mkdir with a pid file inside, taken over when the pid is dead (step_lock lifecycle.sh:1356; merge_lock merge.sh:1100-1104);
  - a hard-linked pid file with a perl-mkdir .reclaim side lock (pid_lock lifecycle.sh:5159-5166);
  - an O_CREAT|O_EXCL file (bin/lib/poll_cache.py:110).
- stale: how a stale holder is broken (find -mmin +1, a dead pid, or never). state_lock takes three lock files for its callers: each caller's row names its own path.
- Add tests/port_locks_test.sh. A primitive is any of: a perl one-liner that calls mkdir; a mkdir without -p, or an ln without -s, in an if, until or while condition or followed by `&& return` or `|| return`; O_EXCL in Python or Go; os.Mkdir or os.Link in Go. A lock function is a function that holds a primitive. A take site is a primitive or a call to a lock function. The test fails on a take site whose (file, function, expr) has no row, or that occurs more often than n, naming its file, function and expr. Each failure line names docs/port/locks.tsv and the row to add. Scan bin/, hooks/, cmd/ and internal/ (skip *_test.go). Source tests/test_helpers.sh first. List files with find (skip __pycache__, *.pyc), not git, so the test runs the same on a copy of the worktree without .git.
- The survey found at least 13 lock paths and 4 protocols. Three perl locks have no *_lock function (agents.sh:1376, :1675; lifecycle.sh:4354).
- Change no lock (HLD non-goals). The primitive rules are heuristics (rules.md:23): the PR lists every match the rule rejected as not a lock, and why.
- Prove it red on a copy without .git: a new perl-mkdir lock in a bin/lib function, a second lock with a new path inside a listed taker, a new caller of state_lock, an O_EXCL open in a .py file, and a deleted row whose lock other rows still take.
- Humanizer over the header lines and the PR body.

**Done when:**
- locks.tsv has one row per take site at the base, each with its lock file, protocol, stale rule and count, and the header gives the number of lock files. tests/port_locks_test.sh passes and goes red on each of the five seeded cases on a copy without .git. The PR lists the rejected matches.
- scripts/select-tests.sh --run passes

---
kind: code
status: later
epic: helpers-shared
depends_on: []
touches: [internal/iface/iface.go:Repo, internal/adapter/git/git.go:Run, internal/adapter/git/git_test.go, internal/report/git.go, internal/report/git_compare_test.go]
estimate_lines: 230
---

# report's git runner runs as Go through the repo interface: quiet_git, git_fetch and batch_ssh

iface.Repo is empty (internal/iface/iface.go:19). Add the one method this needs: run git in a folder with extra environment, no stdin and a time bound, giving the exit code, stdout and stderr, and a result of its own when the bound passes. The git adapter's Run (internal/adapter/git/git.go) runs git from PATH and kills it at the bound. internal/report: FetchSeconds, BatchSSH, QuietGit (GIT_TERMINAL_PROMPT=0, ssh in batch mode, exit 124 with 'over <seconds> s' past the bound) and GitFetch ('' once fetched, else stderr's last line, else 'exit N'), as bin/lib/report.py:187-209 has them. A comparison test runs report.py's git_fetch and batch_ssh and the Go against a real temp repo (a missing remote, a fetch that works, GIT_SSH_COMMAND set and unset, core.sshCommand set), and against a git stub on PATH that prints its environment or sleeps past a short bound, byte for byte. Other stage-2 epics may add Repo methods: see contradictions.

**Done when:**
- (1) The comparison test passes. (2) It goes red when QuietGit alone drops GIT_TERMINAL_PROMPT=0 or the bound, and when report.py's git_fetch alone returns the first stderr line, each shown on a worktree copy without .git. (3) The adapter's test shows a git that outlives the bound is killed. (4) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

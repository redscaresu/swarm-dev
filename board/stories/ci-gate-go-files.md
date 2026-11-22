---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/files.go, internal/merge/files_test.go, tests/ci_gate_cases/files.cases, tests/ci_gate_cases/files-status.cases]
estimate_lines: 260
risk: high
---

# Go that nothing runs: a PR's files and the workflows on a commit, and the files and files-status modes

Needs core's reads, gh and entry.
Adds pr_files, with its hold, its second read when gh lists fewer files than the PR changes, a renamed file's old path, and its compare form for base...sha, and workflows (ci_gate.py:542-600). Registers files and files-status (:1061-1065). Their unreadable-answer errors embed Python's exception text (:584, :598; contradiction 6). Adds files.cases and files-status.cases.

**Done when:**
- (1) tests/ci_gate_cases_test.sh passes with files and files-status marked go: a full list, a short list read again after its hold, a rename, the status column, the compare form, a .github/workflows listing that 404s, and 'gh listed no files, or fewer than the PR changes'. (2) Each case file goes red on a worktree copy without .git where the Go alone is broken (a rename's old path dropped), and where ci_gate.py alone is; the PR quotes the FAIL lines. (3) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

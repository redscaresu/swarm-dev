---
kind: code
status: later
epic: helpers-ci-gate
depends_on: [ci-gate-go-files]
needs: ci-gate-go-files: pr_files and workflows (internal/merge/files.go). Core: ci-gate-go-triggers (on_filters, Unread), ci-gate-go-globs (covers and the bad-pattern error), ci-gate-go-reads (pages), ci-gate-go-cache-store (Store's whole write), ci-gate-go-pyvalues (Dumps).
touches: [internal/merge/expected.go, internal/merge/expected_test.go]
estimate_lines: 290
risk: high
---

# Go that nothing runs: the workflows a push or a PR's pull_request should start, and head's memo of them

Needs ci-gate-go-files: pr_files and workflows. Needs core's triggers, globs, reads, cache-store and pyvalues.
Adds expected for a push (ci_gate.py:602-611), pr_tree, inactive and pr_expected for a pull_request (:613-656), and head_expected's memo (:675-683): the file that keeps pr_expected's answer as json.dump writes [want, unread], read back on later polls, and read again from GitHub when it is missing or unreadable. pr_expected treats Unread and the bad-pattern error alike ('triggers not read: <why>'); expected adds the path to an Unread and lets the bad-pattern error end the run (:607-610). pr_tree's error embeds Python's exception text (:630; contradiction 6).

**Done when:**
- (1) Go tests through a fake CodeHost and Store, each want ci_gate.py's on the same answers (the PR shows the python3 runs): expected over a push filter that covers the change, one that does not, and an Unread workflow; pr_tree on a merge commit that merges the head, a stale one, a 404 and a 422; inactive's disabled workflow left out; pr_expected with a types list without synchronize, an unread workflow, a bad pattern, and over 300 files. (2) The memo the Go writes has python3's json.dump bytes, and a memo Python wrote is read with no workflow read. (3) Each new test goes red on a worktree copy without .git where its rule is broken; the PR quotes the FAIL lines. (4) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: code
status: blocked
epic: merge-safety
depends_on: [dropped-lines-scan]
needs: [dropped-lines-scan: bin/lib/dropped_lines.py, its arguments, output line and exit codes]
touches: [bin/lib/merge.sh:dropped_lines (new), bin/swarm.sh:dropped-lines dispatch arm (new), bin/swarm.sh:dropped-lines usage line (new), bin/swarm.sh:READ_ONLY_COMMANDS, tests/dropped_lines_test.sh:command cases, docs/reference.md:dropped-lines command row (new, in Commands)]
estimate_lines: 220
easy: false
---

# swarm.sh dropped-lines <owner/repo> <n> <head> <base>: a PR's dropped base lines, read-only

From dropped-lines-scan it uses bin/lib/dropped_lines.py: arguments <repo-dir> <base> <head> [<merge sha>...], output `<sha7> <file>: <text>`, exit 0 none, 1 lines, 2 cannot check. New `dropped_lines` in bin/lib/merge.sh, a `dropped-lines` dispatch arm beside merge (swarm.sh:621), a usage line, and the name in READ_ONLY_COMMANDS (swarm.sh:665), since it changes nothing on the board. Steps: check the arguments as merge_pr does (owner/repo and base patterns, merge.sh:842-852; n digits; head 40 hex), else exit 2 with the usage. Read the PR's commits once with gh (`repos/<r>/pulls/<n>/commits`, paginated, each read bounded by BASE_MOVED_WAIT with `within`, as merge_base_update's are): sha, parents, committer login and verification. <head> missing from that list: exit 2, the head moved. No commit with two or more parents other than committer web-flow with a verified signature (merge.sh:561's test): exit 0 with no fetch and no git call. This keeps a merge with no builder merge cheap, and lets merge's tests answer it from their gh stub (contradictions). Otherwise: git below 2.36 prints why and exits 2. The repo is repo_dir of <repo>'s name (swarm.sh:342), and its origin must be <owner/repo> (compared lower case), else exit 2 naming both. Fetch refs/pull/<n>/head and <base> without racing another run on FETCH_HEAD (a private ref or --no-write-fetch-head; say which in the PR). The fetched commit must be <head>: a stale or moved head exits 2 naming both, and no worktree is read. Then run dropped_lines.py on origin/<base>, <head> and the merges that are not web-flow verified, print what it prints and exit with its code. Web-flow verified merges are skipped as the epic says (contradictions). Docs: the command's row in docs/reference.md § Commands. Every call fetches and verifies refs/pull/<n>/head against <head>, including the no-merge path, and derives the merge commits from that commit, never from PR-commit metadata alone. Only merges proven to be update-branch merges (the sha merge_base_update recorded as base-merged) are skipped; any other web-flow merge, a conflict resolved in GitHub's web editor included, is scanned. Exit 1 means lines found only when it prints at least one well-formed `<sha7> <file>: <text>` line; die and set -e stops get their own exit code (a trap, as wait-pr has, bin/swarm.sh:80-85).

**Done when:**
- tests/dropped_lines_test.sh command cases (a real bare origin with refs/pull/7/head pushed, a gh stub for the commits read): a PR whose builder merge dropped a base line prints it and exits 1.
- A PR with no merge commit, and one whose only merge is a recorded base-merged update, exit 0 after refs/pull/7/head is fetched and found equal to <head>; with refs/pull/7/head another commit, the same PRs exit 2.
- Stale fetch: refs/pull/7/head on origin is another commit than <head>, so exit 2 with a line naming both. <head> absent from gh's list: exit 2.
- A git stub first on PATH answering `git version 2.35.0`, on a PR that has a builder merge: exit 2 with a line naming 2.36.
- A repo whose origin is not <owner/repo>: exit 2 naming both.
- Running `swarm.sh dropped-lines` adds no line to events.tsv.
- Copy-aside proof: removing the fetched-commit compare turns the stale case red.
- shellcheck and tests/doc_check_test.sh pass with the § Commands row.
- A stale <head> on the no-merge path exits 2, naming the head it found.
- A web-flow merge that is not a recorded base-merged sha, and that drops a base line, is reported.
- A die inside the command exits with the error code, not 1.

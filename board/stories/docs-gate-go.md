---
kind: code
status: blocked
epic: ship-gates
depends_on: [lead-open-window]
needs: lead-open-window (the user's merge of the merge = human PR, so this PR's review agent hands it to the user)
touches: [bin/lib/merge.sh:release_docs Go tree in the own repo, bin/lib/merge.sh:release_check release_docs call, tests/merge_rules_test.sh:docs gate Go cases, docs/reference-merging.md:--release docs check (§ Merging), AGENTS.md:release paragraph (Working on this repository), commands/swarm.md:release arm docs gate]
estimate_lines: 140
risk: high
---

# In swarm-dev's own repo, the release docs gate counts the Go tree

Uses lead-open-window's **You:** step: with `merge = human` on main, this PR's review agent hands it
to the user.

Split from the patch gate (patch-gate-port) so that each PR changes one behaviour.

Today `merge --release` refuses a bump while `bin/`, `commands/` or `hooks/` changed since the tag
and README.md, AGENTS.md and `docs/` did not (release_docs, the pathspec at merge.sh:3028). In the
plugin's own repo, that code pathspec also takes `cmd`, `internal` and `go.mod`. The refusal names
those paths as it names `bin/` paths. Go test files count as code. The `commands/*.md` carve-out
stays for commands only. In every other repo nothing changes.

"The plugin's own repo" means the release PR's repo, lower-cased, equals plugin_repo. release_check
gets the repo as typed in the URL (merge.sh:1224, then :2884), and plugin_repo is lower case
(merge.sh:2717-2722); compare them as release_upgrade does (merge.sh:2654). When plugin_repo cannot
answer, count `cmd`, `internal` and `go.mod` (fail closed), as protected-go-paths does.

Docs, one new sentence each, never lengthening a sentence that lists the paths:
docs/reference-merging.md (the `--release` docs check), AGENTS.md's release paragraph, and
commands/swarm.md's release arm.

New cases drive `swarm.sh merge --release` from outside, with merge_rules_test.sh's release fixture
(:84-116, the plugin's repo read from plugin.json as at :318). More than two proofs, so use the
worktree copy.

**Done when:**
- In the plugin's own repo, `merge --release` refuses a bump when only cmd/x/main.go changed since
  the tag, and does the same for internal/guard/x.go and for go.mod, one case each, naming the path;
  each case goes red when its path leaves the pathspec (shown on a worktree copy, FAIL lines quoted)
- The same release passes with a docs/ change beside the Go change, and passes with a
  `Docs: none — <reason>` line
- A release PR URL for the own repo written in mixed case is still refused for cmd/x/main.go, and
  passes when the lower-casing is removed (shown on the copy)
- With plugin.json's repository unreadable, a release whose only change is internal/x.go is refused;
  with the fail-closed branch removed it passes (shown on the copy)
- In o/r, a release whose only change is internal/x.go passes the docs gate, as today
- scripts/select-tests.sh --run passes

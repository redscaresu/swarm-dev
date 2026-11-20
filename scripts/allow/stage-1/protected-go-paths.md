---
story: protected-go-paths
pr: 1038
kind: stage
---

# merge holds a story PR that changes the plugin's own protected paths, and grants puts it under no HLD

PR #1038 made five more paths ones only the user merges, in the plugin's own repo (plugin_repo, read from
the tree's .claude-plugin/plugin.json): internal/guard/, internal/merge/, internal/release/,
internal/agentenv/ and .claude-plugin/.

- usage: the merge line names the five paths.
- go_paths_guard, go_paths_merge, go_paths_release, go_paths_agentenv and go_paths_plugin: under
  merge = agent, a story PR in the plugin's own repo that changes one of them was merged, its CI on
  main read and its story finished. Now merge holds it after the pinned compare read: a held: line on
  stderr, exit 1, a merge event with hold=protected, and the hold recorded on the story's board state.
  None of the merge's later gh calls, stub reads or herdr call happen.
- go_paths_grants: swarm.sh grants on such a PR printed the HLD over its story and merge. Now it prints
  none, before it reads the story's file at the head.

## usage stdout

```diff
-#   swarm.sh merge [--board|--release [--upgrade]] [--head <sha>] <pr-url>  merge a green PR in review with its head pinned, wait for CI on the merge commit, then reconcile; with merge = agent, by any route, held for the user when a story listing it, or one it stacks on, has costs: money (or any value but none), and a story PR held for the user when it changes .claude/, .github/, hooks/ or a root Makefile (the user merges it by hand); --board: a board-only PR; --release: a PR into the project's base that changes only the version in .claude-plugin/plugin.json, no reconcile; with merge = human, a story or board PR only under an agreed HLD that grants merge, and even then held for the user when it has costs: money; --release only when at least one story merged since the last tag and every one of them is under an HLD that grants release; a story or --board PR that sets an epic active with no ticket (agreed:, parent:, an HLD granting epics, or lead_epics = on), or above the stage origin's base allows (its newest v-tag below the minor before the stage, and no epic of that stage active there), is refused (a story PR's epics are read only with lead_epics = off); under either merge mode, a story or --board PR whose own merge of the base dropped a line of the base that its head has not put back (dropped-lines, on the pinned head) is held for the user, as is one whose merges cannot be checked, and one whose head moved on GitHub meanwhile is refused for a new review
+#   swarm.sh merge [--board|--release [--upgrade]] [--head <sha>] <pr-url>  merge a green PR in review with its head pinned, wait for CI on the merge commit, then reconcile; with merge = agent, by any route, held for the user when a story listing it, or one it stacks on, has costs: money (or any value but none), and a story PR held for the user when it changes .claude/, .github/, hooks/ or a root Makefile, or in this plugin's own repo internal/guard/, internal/merge/, internal/release/, internal/agentenv/ or .claude-plugin/ (the user merges it by hand); --board: a board-only PR; --release: a PR into the project's base that changes only the version in .claude-plugin/plugin.json, no reconcile; with merge = human, a story or board PR only under an agreed HLD that grants merge, and even then held for the user when it has costs: money; --release only when at least one story merged since the last tag and every one of them is under an HLD that grants release; a story or --board PR that sets an epic active with no ticket (agreed:, parent:, an HLD granting epics, or lead_epics = on), or above the stage origin's base allows (its newest v-tag below the minor before the stage, and no epic of that stage active there), is refused (a story PR's epics are read only with lead_epics = off); under either merge mode, a story or --board PR whose own merge of the base dropped a line of the base that its head has not put back (dropped-lines, on the pinned head) is held for the user, as is one whose merges cannot be checked, and one whose head moved on GitHub meanwhile is refused for a new review
```

## go_paths_guard stdout

```diff
-merged: https://github.com/redscaresu/swarm-dev/pull/7 (squash, head 1111111, merge commit aaaaaaa); waiting for CI on main
-main-ci: ok
-deleted: <root>/proj/docs/stories/s.md
```

## go_paths_guard stderr

```diff
^
+swarm: merge: held: s changes internal/guard/x.go, which only the user merges; the user merges it
```

## go_paths_guard exit

```diff
-0
+1
```

## go_paths_guard files

```diff
-deleted <root>/proj/docs/stories/s.md
-written <root>/agents.log
```

```diff
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.checks.n
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.runs.n
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.status.n
-written <root>/fx/branch.n
```

```diff
-written <root>/fx/mergecommit
-written <root>/fx/mq.n
-written <root>/fx/rules.n
-written <root>/fx/state
-written <root>/fx/wf.ci.yml.n
```

```diff
-written <root>/fx/workflows.n
```

```diff
 written <root>/gh.log
+written <root>/proj/.swarm/board-state/stories/s
```

## go_paths_guard file:<root>/fx/files.n

```diff
-2
+1
```

## go_paths_guard file:<root>/gh.log

```diff
-api --paginate --jq .[] | "\(.sha) \(.parents | length)" repos/redscaresu/swarm-dev/pulls/7/commits?per_page=100
-repo view redscaresu/swarm-dev --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed
-api graphql -f o=redscaresu -f r=swarm-dev -f b=main -f query=query($o: String!, $r: String!, $b: String!) { repository(owner: $o, name: $r) { mergeQueue(branch: $b) { id } } }
-api repos/redscaresu/swarm-dev/compare/1111111111111111111111111111111111111111...main
-pr merge 7 --repo redscaresu/swarm-dev --squash --match-head-commit 1111111111111111111111111111111111111111
-pr view 7 --repo redscaresu/swarm-dev --json state,mergeCommit
-api --paginate repos/redscaresu/swarm-dev/rules/branches/main?per_page=100
-api repos/redscaresu/swarm-dev/branches/main/protection
-api repos/redscaresu/swarm-dev/contents/.github/workflows?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-api -H Accept: application/vnd.github.raw repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-api --paginate repos/redscaresu/swarm-dev/pulls/7/files?per_page=100
-api --paginate repos/redscaresu/swarm-dev/actions/runs?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&per_page=100
-api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs?per_page=100
-api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status?per_page=100
-pr view https://github.com/redscaresu/swarm-dev/pull/7 --json state
```

## go_paths_guard file:<root>/proj/.swarm/board-state/stories/s

```diff
^
+protected: https://github.com/redscaresu/swarm-dev/pull/7 1111111111111111111111111111111111111111 1767225600 internal/guard/x.go
+protected@base:
```

## go_paths_guard file:<root>/proj/.swarm/events.tsv

```diff
-<time>	merge	s	-	ok ~~ version=<version>
-<time>	main-ci	s	-	ok ~~ version=<version>
-<time>	reconcile	s	-	ok (finished) ~~ version=<version>
+<time>	merge	s	-	held: s changes internal/guard/x.go, which only the user merges; the user merges it ~~ hold=protected version=<version>
```

## go_paths_guard file:<root>/proj/.swarm/gh-calls.tsv

```diff
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/pulls/:id/commits	rest	paginate	0
-<time>	-	swarm.sh merge	repo view	graphql	-	0
-<time>	-	swarm.sh merge	api graphql	graphql	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/compare/:id	rest	-	0
-<time>	-	swarm.sh merge	pr merge	graphql	-	0
-<time>	-	swarm.sh merge	pr view	graphql	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/rules/branches/main	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/branches/main/protection	rest	-	1
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/contents/.github/workflows	rest	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml	rest	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/pulls/:id/files	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/actions/runs	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status	rest	paginate	0
-<time>	-	swarm.sh merge	pr view	graphql	-	0
```

## go_paths_guard calls:fg

```diff
-gh api --paginate --jq .\[\]\ \|\ \"\\\(.sha\)\ \\\(.parents\ \|\ length\)\" repos/redscaresu/swarm-dev/pulls/7/commits\?per_page=100
-gh repo view redscaresu/swarm-dev --json squashMergeAllowed\,mergeCommitAllowed\,rebaseMergeAllowed
-gh api graphql -f o=redscaresu -f r=swarm-dev -f b=main -f query=query\(\$o:\ String\!\,\ \$r:\ String\!\,\ \$b:\ String\!\)\ \{\ repository\(owner:\ \$o\,\ name:\ \$r\)\ \{\ mergeQueue\(branch:\ \$b\)\ \{\ id\ \}\ \}\ \}
-gh api repos/redscaresu/swarm-dev/compare/1111111111111111111111111111111111111111...main
-gh pr merge 7 --repo redscaresu/swarm-dev --squash --match-head-commit 1111111111111111111111111111111111111111
-gh pr view 7 --repo redscaresu/swarm-dev --json state\,mergeCommit
-gh api --paginate repos/redscaresu/swarm-dev/rules/branches/main\?per_page=100
-gh api repos/redscaresu/swarm-dev/branches/main/protection
-gh api repos/redscaresu/swarm-dev/contents/.github/workflows\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-gh api -H Accept:\ application/vnd.github.raw repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-gh api --paginate repos/redscaresu/swarm-dev/pulls/7/files\?per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/actions/runs\?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\&per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs\?per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status\?per_page=100
-gh pr view https://github.com/redscaresu/swarm-dev/pull/7 --json state
-herdr agent list
```

## go_paths_merge stdout

```diff
-merged: https://github.com/redscaresu/swarm-dev/pull/7 (squash, head 1111111, merge commit aaaaaaa); waiting for CI on main
-main-ci: ok
-deleted: <root>/proj/docs/stories/s.md
```

## go_paths_merge stderr

```diff
^
+swarm: merge: held: s changes internal/merge/x.go, which only the user merges; the user merges it
```

## go_paths_merge exit

```diff
-0
+1
```

## go_paths_merge files

```diff
-deleted <root>/proj/docs/stories/s.md
-written <root>/agents.log
```

```diff
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.checks.n
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.runs.n
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.status.n
-written <root>/fx/branch.n
```

```diff
-written <root>/fx/mergecommit
-written <root>/fx/mq.n
-written <root>/fx/rules.n
-written <root>/fx/state
-written <root>/fx/wf.ci.yml.n
```

```diff
-written <root>/fx/workflows.n
```

```diff
 written <root>/gh.log
+written <root>/proj/.swarm/board-state/stories/s
```

## go_paths_merge file:<root>/fx/files.n

```diff
-2
+1
```

## go_paths_merge file:<root>/gh.log

```diff
-api --paginate --jq .[] | "\(.sha) \(.parents | length)" repos/redscaresu/swarm-dev/pulls/7/commits?per_page=100
-repo view redscaresu/swarm-dev --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed
-api graphql -f o=redscaresu -f r=swarm-dev -f b=main -f query=query($o: String!, $r: String!, $b: String!) { repository(owner: $o, name: $r) { mergeQueue(branch: $b) { id } } }
-api repos/redscaresu/swarm-dev/compare/1111111111111111111111111111111111111111...main
-pr merge 7 --repo redscaresu/swarm-dev --squash --match-head-commit 1111111111111111111111111111111111111111
-pr view 7 --repo redscaresu/swarm-dev --json state,mergeCommit
-api --paginate repos/redscaresu/swarm-dev/rules/branches/main?per_page=100
-api repos/redscaresu/swarm-dev/branches/main/protection
-api repos/redscaresu/swarm-dev/contents/.github/workflows?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-api -H Accept: application/vnd.github.raw repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-api --paginate repos/redscaresu/swarm-dev/pulls/7/files?per_page=100
-api --paginate repos/redscaresu/swarm-dev/actions/runs?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&per_page=100
-api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs?per_page=100
-api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status?per_page=100
-pr view https://github.com/redscaresu/swarm-dev/pull/7 --json state
```

## go_paths_merge file:<root>/proj/.swarm/board-state/stories/s

```diff
^
+protected: https://github.com/redscaresu/swarm-dev/pull/7 1111111111111111111111111111111111111111 1767225600 internal/merge/x.go
+protected@base:
```

## go_paths_merge file:<root>/proj/.swarm/events.tsv

```diff
-<time>	merge	s	-	ok ~~ version=<version>
-<time>	main-ci	s	-	ok ~~ version=<version>
-<time>	reconcile	s	-	ok (finished) ~~ version=<version>
+<time>	merge	s	-	held: s changes internal/merge/x.go, which only the user merges; the user merges it ~~ hold=protected version=<version>
```

## go_paths_merge file:<root>/proj/.swarm/gh-calls.tsv

```diff
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/pulls/:id/commits	rest	paginate	0
-<time>	-	swarm.sh merge	repo view	graphql	-	0
-<time>	-	swarm.sh merge	api graphql	graphql	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/compare/:id	rest	-	0
-<time>	-	swarm.sh merge	pr merge	graphql	-	0
-<time>	-	swarm.sh merge	pr view	graphql	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/rules/branches/main	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/branches/main/protection	rest	-	1
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/contents/.github/workflows	rest	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml	rest	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/pulls/:id/files	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/actions/runs	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status	rest	paginate	0
-<time>	-	swarm.sh merge	pr view	graphql	-	0
```

## go_paths_merge calls:fg

```diff
-gh api --paginate --jq .\[\]\ \|\ \"\\\(.sha\)\ \\\(.parents\ \|\ length\)\" repos/redscaresu/swarm-dev/pulls/7/commits\?per_page=100
-gh repo view redscaresu/swarm-dev --json squashMergeAllowed\,mergeCommitAllowed\,rebaseMergeAllowed
-gh api graphql -f o=redscaresu -f r=swarm-dev -f b=main -f query=query\(\$o:\ String\!\,\ \$r:\ String\!\,\ \$b:\ String\!\)\ \{\ repository\(owner:\ \$o\,\ name:\ \$r\)\ \{\ mergeQueue\(branch:\ \$b\)\ \{\ id\ \}\ \}\ \}
-gh api repos/redscaresu/swarm-dev/compare/1111111111111111111111111111111111111111...main
-gh pr merge 7 --repo redscaresu/swarm-dev --squash --match-head-commit 1111111111111111111111111111111111111111
-gh pr view 7 --repo redscaresu/swarm-dev --json state\,mergeCommit
-gh api --paginate repos/redscaresu/swarm-dev/rules/branches/main\?per_page=100
-gh api repos/redscaresu/swarm-dev/branches/main/protection
-gh api repos/redscaresu/swarm-dev/contents/.github/workflows\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-gh api -H Accept:\ application/vnd.github.raw repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-gh api --paginate repos/redscaresu/swarm-dev/pulls/7/files\?per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/actions/runs\?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\&per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs\?per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status\?per_page=100
-gh pr view https://github.com/redscaresu/swarm-dev/pull/7 --json state
-herdr agent list
```

## go_paths_release stdout

```diff
-merged: https://github.com/redscaresu/swarm-dev/pull/7 (squash, head 1111111, merge commit aaaaaaa); waiting for CI on main
-main-ci: ok
-deleted: <root>/proj/docs/stories/s.md
```

## go_paths_release stderr

```diff
^
+swarm: merge: held: s changes internal/release/x.go, which only the user merges; the user merges it
```

## go_paths_release exit

```diff
-0
+1
```

## go_paths_release files

```diff
-deleted <root>/proj/docs/stories/s.md
-written <root>/agents.log
```

```diff
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.checks.n
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.runs.n
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.status.n
-written <root>/fx/branch.n
```

```diff
-written <root>/fx/mergecommit
-written <root>/fx/mq.n
-written <root>/fx/rules.n
-written <root>/fx/state
-written <root>/fx/wf.ci.yml.n
```

```diff
-written <root>/fx/workflows.n
```

```diff
 written <root>/gh.log
+written <root>/proj/.swarm/board-state/stories/s
```

## go_paths_release file:<root>/fx/files.n

```diff
-2
+1
```

## go_paths_release file:<root>/gh.log

```diff
-api --paginate --jq .[] | "\(.sha) \(.parents | length)" repos/redscaresu/swarm-dev/pulls/7/commits?per_page=100
-repo view redscaresu/swarm-dev --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed
-api graphql -f o=redscaresu -f r=swarm-dev -f b=main -f query=query($o: String!, $r: String!, $b: String!) { repository(owner: $o, name: $r) { mergeQueue(branch: $b) { id } } }
-api repos/redscaresu/swarm-dev/compare/1111111111111111111111111111111111111111...main
-pr merge 7 --repo redscaresu/swarm-dev --squash --match-head-commit 1111111111111111111111111111111111111111
-pr view 7 --repo redscaresu/swarm-dev --json state,mergeCommit
-api --paginate repos/redscaresu/swarm-dev/rules/branches/main?per_page=100
-api repos/redscaresu/swarm-dev/branches/main/protection
-api repos/redscaresu/swarm-dev/contents/.github/workflows?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-api -H Accept: application/vnd.github.raw repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-api --paginate repos/redscaresu/swarm-dev/pulls/7/files?per_page=100
-api --paginate repos/redscaresu/swarm-dev/actions/runs?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&per_page=100
-api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs?per_page=100
-api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status?per_page=100
-pr view https://github.com/redscaresu/swarm-dev/pull/7 --json state
```

## go_paths_release file:<root>/proj/.swarm/board-state/stories/s

```diff
^
+protected: https://github.com/redscaresu/swarm-dev/pull/7 1111111111111111111111111111111111111111 1767225600 internal/release/x.go
+protected@base:
```

## go_paths_release file:<root>/proj/.swarm/events.tsv

```diff
-<time>	merge	s	-	ok ~~ version=<version>
-<time>	main-ci	s	-	ok ~~ version=<version>
-<time>	reconcile	s	-	ok (finished) ~~ version=<version>
+<time>	merge	s	-	held: s changes internal/release/x.go, which only the user merges; the user merges it ~~ hold=protected version=<version>
```

## go_paths_release file:<root>/proj/.swarm/gh-calls.tsv

```diff
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/pulls/:id/commits	rest	paginate	0
-<time>	-	swarm.sh merge	repo view	graphql	-	0
-<time>	-	swarm.sh merge	api graphql	graphql	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/compare/:id	rest	-	0
-<time>	-	swarm.sh merge	pr merge	graphql	-	0
-<time>	-	swarm.sh merge	pr view	graphql	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/rules/branches/main	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/branches/main/protection	rest	-	1
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/contents/.github/workflows	rest	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml	rest	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/pulls/:id/files	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/actions/runs	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status	rest	paginate	0
-<time>	-	swarm.sh merge	pr view	graphql	-	0
```

## go_paths_release calls:fg

```diff
-gh api --paginate --jq .\[\]\ \|\ \"\\\(.sha\)\ \\\(.parents\ \|\ length\)\" repos/redscaresu/swarm-dev/pulls/7/commits\?per_page=100
-gh repo view redscaresu/swarm-dev --json squashMergeAllowed\,mergeCommitAllowed\,rebaseMergeAllowed
-gh api graphql -f o=redscaresu -f r=swarm-dev -f b=main -f query=query\(\$o:\ String\!\,\ \$r:\ String\!\,\ \$b:\ String\!\)\ \{\ repository\(owner:\ \$o\,\ name:\ \$r\)\ \{\ mergeQueue\(branch:\ \$b\)\ \{\ id\ \}\ \}\ \}
-gh api repos/redscaresu/swarm-dev/compare/1111111111111111111111111111111111111111...main
-gh pr merge 7 --repo redscaresu/swarm-dev --squash --match-head-commit 1111111111111111111111111111111111111111
-gh pr view 7 --repo redscaresu/swarm-dev --json state\,mergeCommit
-gh api --paginate repos/redscaresu/swarm-dev/rules/branches/main\?per_page=100
-gh api repos/redscaresu/swarm-dev/branches/main/protection
-gh api repos/redscaresu/swarm-dev/contents/.github/workflows\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-gh api -H Accept:\ application/vnd.github.raw repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-gh api --paginate repos/redscaresu/swarm-dev/pulls/7/files\?per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/actions/runs\?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\&per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs\?per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status\?per_page=100
-gh pr view https://github.com/redscaresu/swarm-dev/pull/7 --json state
-herdr agent list
```

## go_paths_agentenv stdout

```diff
-merged: https://github.com/redscaresu/swarm-dev/pull/7 (squash, head 1111111, merge commit aaaaaaa); waiting for CI on main
-main-ci: ok
-deleted: <root>/proj/docs/stories/s.md
```

## go_paths_agentenv stderr

```diff
^
+swarm: merge: held: s changes internal/agentenv/x.go, which only the user merges; the user merges it
```

## go_paths_agentenv exit

```diff
-0
+1
```

## go_paths_agentenv files

```diff
-deleted <root>/proj/docs/stories/s.md
-written <root>/agents.log
```

```diff
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.checks.n
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.runs.n
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.status.n
-written <root>/fx/branch.n
```

```diff
-written <root>/fx/mergecommit
-written <root>/fx/mq.n
-written <root>/fx/rules.n
-written <root>/fx/state
-written <root>/fx/wf.ci.yml.n
```

```diff
-written <root>/fx/workflows.n
```

```diff
 written <root>/gh.log
+written <root>/proj/.swarm/board-state/stories/s
```

## go_paths_agentenv file:<root>/fx/files.n

```diff
-2
+1
```

## go_paths_agentenv file:<root>/gh.log

```diff
-api --paginate --jq .[] | "\(.sha) \(.parents | length)" repos/redscaresu/swarm-dev/pulls/7/commits?per_page=100
-repo view redscaresu/swarm-dev --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed
-api graphql -f o=redscaresu -f r=swarm-dev -f b=main -f query=query($o: String!, $r: String!, $b: String!) { repository(owner: $o, name: $r) { mergeQueue(branch: $b) { id } } }
-api repos/redscaresu/swarm-dev/compare/1111111111111111111111111111111111111111...main
-pr merge 7 --repo redscaresu/swarm-dev --squash --match-head-commit 1111111111111111111111111111111111111111
-pr view 7 --repo redscaresu/swarm-dev --json state,mergeCommit
-api --paginate repos/redscaresu/swarm-dev/rules/branches/main?per_page=100
-api repos/redscaresu/swarm-dev/branches/main/protection
-api repos/redscaresu/swarm-dev/contents/.github/workflows?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-api -H Accept: application/vnd.github.raw repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-api --paginate repos/redscaresu/swarm-dev/pulls/7/files?per_page=100
-api --paginate repos/redscaresu/swarm-dev/actions/runs?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&per_page=100
-api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs?per_page=100
-api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status?per_page=100
-pr view https://github.com/redscaresu/swarm-dev/pull/7 --json state
```

## go_paths_agentenv file:<root>/proj/.swarm/board-state/stories/s

```diff
^
+protected: https://github.com/redscaresu/swarm-dev/pull/7 1111111111111111111111111111111111111111 1767225600 internal/agentenv/x.go
+protected@base:
```

## go_paths_agentenv file:<root>/proj/.swarm/events.tsv

```diff
-<time>	merge	s	-	ok ~~ version=<version>
-<time>	main-ci	s	-	ok ~~ version=<version>
-<time>	reconcile	s	-	ok (finished) ~~ version=<version>
+<time>	merge	s	-	held: s changes internal/agentenv/x.go, which only the user merges; the user merges it ~~ hold=protected version=<version>
```

## go_paths_agentenv file:<root>/proj/.swarm/gh-calls.tsv

```diff
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/pulls/:id/commits	rest	paginate	0
-<time>	-	swarm.sh merge	repo view	graphql	-	0
-<time>	-	swarm.sh merge	api graphql	graphql	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/compare/:id	rest	-	0
-<time>	-	swarm.sh merge	pr merge	graphql	-	0
-<time>	-	swarm.sh merge	pr view	graphql	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/rules/branches/main	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/branches/main/protection	rest	-	1
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/contents/.github/workflows	rest	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml	rest	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/pulls/:id/files	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/actions/runs	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status	rest	paginate	0
-<time>	-	swarm.sh merge	pr view	graphql	-	0
```

## go_paths_agentenv calls:fg

```diff
-gh api --paginate --jq .\[\]\ \|\ \"\\\(.sha\)\ \\\(.parents\ \|\ length\)\" repos/redscaresu/swarm-dev/pulls/7/commits\?per_page=100
-gh repo view redscaresu/swarm-dev --json squashMergeAllowed\,mergeCommitAllowed\,rebaseMergeAllowed
-gh api graphql -f o=redscaresu -f r=swarm-dev -f b=main -f query=query\(\$o:\ String\!\,\ \$r:\ String\!\,\ \$b:\ String\!\)\ \{\ repository\(owner:\ \$o\,\ name:\ \$r\)\ \{\ mergeQueue\(branch:\ \$b\)\ \{\ id\ \}\ \}\ \}
-gh api repos/redscaresu/swarm-dev/compare/1111111111111111111111111111111111111111...main
-gh pr merge 7 --repo redscaresu/swarm-dev --squash --match-head-commit 1111111111111111111111111111111111111111
-gh pr view 7 --repo redscaresu/swarm-dev --json state\,mergeCommit
-gh api --paginate repos/redscaresu/swarm-dev/rules/branches/main\?per_page=100
-gh api repos/redscaresu/swarm-dev/branches/main/protection
-gh api repos/redscaresu/swarm-dev/contents/.github/workflows\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-gh api -H Accept:\ application/vnd.github.raw repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-gh api --paginate repos/redscaresu/swarm-dev/pulls/7/files\?per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/actions/runs\?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\&per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs\?per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status\?per_page=100
-gh pr view https://github.com/redscaresu/swarm-dev/pull/7 --json state
-herdr agent list
```

## go_paths_plugin stdout

```diff
-merged: https://github.com/redscaresu/swarm-dev/pull/7 (squash, head 1111111, merge commit aaaaaaa); waiting for CI on main
-main-ci: ok
-deleted: <root>/proj/docs/stories/s.md
```

## go_paths_plugin stderr

```diff
^
+swarm: merge: held: s changes .claude-plugin/marketplace.json, which only the user merges; the user merges it
```

## go_paths_plugin exit

```diff
-0
+1
```

## go_paths_plugin files

```diff
-deleted <root>/proj/docs/stories/s.md
-written <root>/agents.log
```

```diff
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.checks.n
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.runs.n
-written <root>/fx/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.status.n
-written <root>/fx/branch.n
```

```diff
-written <root>/fx/mergecommit
-written <root>/fx/mq.n
-written <root>/fx/rules.n
-written <root>/fx/state
-written <root>/fx/wf.ci.yml.n
```

```diff
-written <root>/fx/workflows.n
```

```diff
 written <root>/gh.log
+written <root>/proj/.swarm/board-state/stories/s
```

## go_paths_plugin file:<root>/fx/files.n

```diff
-2
+1
```

## go_paths_plugin file:<root>/gh.log

```diff
-api --paginate --jq .[] | "\(.sha) \(.parents | length)" repos/redscaresu/swarm-dev/pulls/7/commits?per_page=100
-repo view redscaresu/swarm-dev --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed
-api graphql -f o=redscaresu -f r=swarm-dev -f b=main -f query=query($o: String!, $r: String!, $b: String!) { repository(owner: $o, name: $r) { mergeQueue(branch: $b) { id } } }
-api repos/redscaresu/swarm-dev/compare/1111111111111111111111111111111111111111...main
-pr merge 7 --repo redscaresu/swarm-dev --squash --match-head-commit 1111111111111111111111111111111111111111
-pr view 7 --repo redscaresu/swarm-dev --json state,mergeCommit
-api --paginate repos/redscaresu/swarm-dev/rules/branches/main?per_page=100
-api repos/redscaresu/swarm-dev/branches/main/protection
-api repos/redscaresu/swarm-dev/contents/.github/workflows?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-api -H Accept: application/vnd.github.raw repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-api --paginate repos/redscaresu/swarm-dev/pulls/7/files?per_page=100
-api --paginate repos/redscaresu/swarm-dev/actions/runs?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&per_page=100
-api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs?per_page=100
-api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status?per_page=100
-pr view https://github.com/redscaresu/swarm-dev/pull/7 --json state
```

## go_paths_plugin file:<root>/proj/.swarm/board-state/stories/s

```diff
^
+protected: https://github.com/redscaresu/swarm-dev/pull/7 1111111111111111111111111111111111111111 1767225600 .claude-plugin/marketplace.json
+protected@base:
```

## go_paths_plugin file:<root>/proj/.swarm/events.tsv

```diff
-<time>	merge	s	-	ok ~~ version=<version>
-<time>	main-ci	s	-	ok ~~ version=<version>
-<time>	reconcile	s	-	ok (finished) ~~ version=<version>
+<time>	merge	s	-	held: s changes .claude-plugin/marketplace.json, which only the user merges; the user merges it ~~ hold=protected version=<version>
```

## go_paths_plugin file:<root>/proj/.swarm/gh-calls.tsv

```diff
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/pulls/:id/commits	rest	paginate	0
-<time>	-	swarm.sh merge	repo view	graphql	-	0
-<time>	-	swarm.sh merge	api graphql	graphql	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/compare/:id	rest	-	0
-<time>	-	swarm.sh merge	pr merge	graphql	-	0
-<time>	-	swarm.sh merge	pr view	graphql	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/rules/branches/main	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/branches/main/protection	rest	-	1
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/contents/.github/workflows	rest	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml	rest	-	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/pulls/:id/files	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/actions/runs	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status	rest	paginate	0
-<time>	-	swarm.sh merge	pr view	graphql	-	0
```

## go_paths_plugin calls:fg

```diff
-gh api --paginate --jq .\[\]\ \|\ \"\\\(.sha\)\ \\\(.parents\ \|\ length\)\" repos/redscaresu/swarm-dev/pulls/7/commits\?per_page=100
-gh repo view redscaresu/swarm-dev --json squashMergeAllowed\,mergeCommitAllowed\,rebaseMergeAllowed
-gh api graphql -f o=redscaresu -f r=swarm-dev -f b=main -f query=query\(\$o:\ String\!\,\ \$r:\ String\!\,\ \$b:\ String\!\)\ \{\ repository\(owner:\ \$o\,\ name:\ \$r\)\ \{\ mergeQueue\(branch:\ \$b\)\ \{\ id\ \}\ \}\ \}
-gh api repos/redscaresu/swarm-dev/compare/1111111111111111111111111111111111111111...main
-gh pr merge 7 --repo redscaresu/swarm-dev --squash --match-head-commit 1111111111111111111111111111111111111111
-gh pr view 7 --repo redscaresu/swarm-dev --json state\,mergeCommit
-gh api --paginate repos/redscaresu/swarm-dev/rules/branches/main\?per_page=100
-gh api repos/redscaresu/swarm-dev/branches/main/protection
-gh api repos/redscaresu/swarm-dev/contents/.github/workflows\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-gh api -H Accept:\ application/vnd.github.raw repos/redscaresu/swarm-dev/contents/.github/workflows/ci.yml\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-gh api --paginate repos/redscaresu/swarm-dev/pulls/7/files\?per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/actions/runs\?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\&per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs\?per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status\?per_page=100
-gh pr view https://github.com/redscaresu/swarm-dev/pull/7 --json state
-herdr agent list
```

## go_paths_grants stdout

```diff
-<root>/proj/docs/hld/2026-01-01-a.md
-merge
+none
```

## go_paths_grants files

```diff
-written <root>/fx/wf.s.md.n
```

## go_paths_grants file:<root>/gh.log

```diff
-api -H Accept: application/vnd.github.raw repos/redscaresu/swarm-dev/contents/docs/stories/s.md?ref=1111111111111111111111111111111111111111
```

## go_paths_grants file:<root>/proj/.swarm/gh-calls.tsv

```diff
-<time>	-	swarm.sh grants	api repos/redscaresu/swarm-dev/contents/docs/stories/s.md	rest	-	1
```

## go_paths_grants calls:fg

```diff
-gh api -H Accept:\ application/vnd.github.raw repos/redscaresu/swarm-dev/contents/docs/stories/s.md\?ref=1111111111111111111111111111111111111111
```

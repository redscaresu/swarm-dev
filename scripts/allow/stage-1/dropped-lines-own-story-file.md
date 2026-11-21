---
story: dropped-lines-own-story-file
pr: 1021
kind: fix
---

# dropped-lines skips a story PR's own story file when its head deletes it

#1021 is a `fix: true` story.
The flag comes from its story file at 198ceef9 (#1018), since #1021 deleted that file.

A story PR deletes its own story file.
When a board PR adds a line to that file after the branch was cut, the PR's merge of the base drops the line with the file.
v0.31.2 counted that line as dropped, and held the PR for the user (#1003, #1006 and #1008).
From v0.31.3, `swarm.sh dropped-lines --story <slug>` counts no line of that story's file when the head deletes it.
merge's story route passes `--story` (bin/lib/merge.sh:1058).
It does so only when the board is in the PR's repo, which `origin_repo` reads with one `gh repo view` call (bin/lib/merge.sh:390-397).

The fixtures are in tests/diff_fixtures_dropped.sh:

- `usage`: the dropped-lines usage line names `--story`.
- `dropped_story_usage`: a `--story` that is no slug is a usage error on both trees, and the error names `--story`.
- `dropped_own_story`: `--story s` is a usage error on v0.31.2. From v0.31.3 it reads the PR's commits, then the origin with `gh repo view`, and exits 0.
- `dropped_merge_own_story`: v0.31.2 holds story s's PR for the `fix: true` line. From v0.31.3 merge reads the origin, merges the PR, waits for CI on main and reconciles the story.
- `dropped_no_story` has no hunk: with no `--story`, both trees print the line and exit 1.

## dropped_merge_own_story stdout

```diff
^
+merged: https://github.com/o/r/pull/7 (squash, head ef33188, merge commit aaaaaaa); waiting for CI on main
+main-ci: ok
+deleted: <root>/proj/docs/stories/s.md
```

## dropped_merge_own_story stderr

```diff
-swarm: merge: held: s (dropped base lines: 1, first docs/stories/s.md: fix: true); the builder restores them in a commit of its own, or the user reads the PR's answer and merges by hand
```

## dropped_merge_own_story exit

```diff
-1
+0
```

## dropped_merge_own_story files

```diff
-written <root>/proj/.swarm/board-state/stories/s
+deleted <root>/proj/docs/stories/s.md
+written <root>/fx/state
```

## dropped_merge_own_story file:<root>/fx/state

```diff
^
+MERGED
```

## dropped_merge_own_story file:<root>/proj/.swarm/events.tsv

```diff
-<time>	merge	s	-	held: s (dropped base lines: 1, first docs/stories/s.md: fix: true); the builder restores them in a commit of its own, or the user reads the PR's answer and merges by hand ~~ hold=dropped-lines version=<version>
+<time>	merge	s	-	ok ~~ version=<version>
+<time>	main-ci	s	-	ok ~~ version=<version>
+<time>	reconcile	s	-	ok (finished) ~~ version=<version>
```

## dropped_merge_own_story file:<root>/proj/.swarm/gh-calls.tsv

```diff
 <time>	-	swarm.sh merge	api repos/o/r/pulls/:id/commits	rest	paginate	0
 <time>	-	swarm.sh merge	api repos/o/r/pulls/:id/commits	rest	paginate	0
+<time>	-	swarm.sh merge	repo view	graphql	-	0
```

```diff
 <time>	-	swarm.sh merge	api repos/o/r/pulls/:id/commits	rest	paginate	0
 <time>	-	swarm.sh merge	repo view	graphql	-	0
+<time>	-	swarm.sh merge	repo view	graphql	-	0
+<time>	-	swarm.sh merge	api graphql	graphql	-	0
+<time>	-	swarm.sh merge	api repos/o/r/compare/:id	rest	-	0
+<time>	-	swarm.sh merge	pr merge	graphql	-	0
+<time>	-	swarm.sh merge	pr view	graphql	-	0
+<time>	-	swarm.sh merge	api repos/o/r/rules/branches/main	rest	paginate	0
+<time>	-	swarm.sh merge	api repos/o/r/branches/main/protection	rest	-	1
+<time>	-	swarm.sh merge	api repos/o/r/contents/.github/workflows	rest	-	0
+<time>	-	swarm.sh merge	api repos/o/r/contents/.github/workflows/ci.yml	rest	-	0
+<time>	-	swarm.sh merge	api repos/o/r/pulls/:id/files	rest	paginate	0
+<time>	-	swarm.sh merge	api repos/o/r/actions/runs	rest	paginate	0
+<time>	-	swarm.sh merge	api repos/o/r/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs	rest	paginate	0
+<time>	-	swarm.sh merge	api repos/o/r/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status	rest	paginate	0
+<time>	-	swarm.sh merge	pr view	graphql	-	0
```

## dropped_merge_own_story calls:fg

```diff
 gh api --paginate repos/o/r/pulls/7/commits\?per_page=100 --jq .\[\].sha
+gh repo view <root>/origin.git --json nameWithOwner
```

```diff
 gh api --paginate repos/o/r/pulls/7/commits\?per_page=100 --jq .\[\].sha
 gh repo view <root>/origin.git --json nameWithOwner
+gh repo view o/r --json squashMergeAllowed\,mergeCommitAllowed\,rebaseMergeAllowed
+gh api graphql -f o=o -f r=r -f b=main -f query=query\(\$o:\ String\!\,\ \$r:\ String\!\,\ \$b:\ String\!\)\ \{\ repository\(owner:\ \$o\,\ name:\ \$r\)\ \{\ mergeQueue\(branch:\ \$b\)\ \{\ id\ \}\ \}\ \}
+gh api repos/o/r/compare/ef3318880c33c1f48f7474ecd2479bed419ad0ec...main
+gh pr merge 7 --repo o/r --squash --match-head-commit ef3318880c33c1f48f7474ecd2479bed419ad0ec
+gh pr view 7 --repo o/r --json state\,mergeCommit
+gh api --paginate repos/o/r/rules/branches/main\?per_page=100
+gh api repos/o/r/branches/main/protection
+gh api repos/o/r/contents/.github/workflows\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
+gh api -H Accept:\ application/vnd.github.raw repos/o/r/contents/.github/workflows/ci.yml\?ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
+gh api --paginate repos/o/r/pulls/7/files\?per_page=100
+gh api --paginate repos/o/r/actions/runs\?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\&per_page=100
+gh api --paginate repos/o/r/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs\?per_page=100
+gh api --paginate repos/o/r/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/status\?per_page=100
+gh pr view https://github.com/o/r/pull/7 --json state
+herdr agent list
```

## dropped_own_story stderr

```diff
-swarm: dropped-lines: usage: swarm.sh dropped-lines <owner/repo> <n> <40-character head SHA> <base>
```

## dropped_own_story exit

```diff
-2
+0
```

## dropped_own_story files

```diff
^
+written <root>/proj/.swarm/gh-calls.tsv
```

## dropped_own_story file:<root>/proj/.swarm/gh-calls.tsv

```diff
^
+<time>	-	swarm.sh dropped-lines	api repos/o/r/pulls/:id/commits	rest	paginate	0
```

```diff
 <time>	-	swarm.sh dropped-lines	api repos/o/r/pulls/:id/commits	rest	paginate	0
+<time>	-	swarm.sh dropped-lines	repo view	graphql	-	0
```

## dropped_own_story calls:fg

```diff
^
+gh api --paginate repos/o/r/pulls/7/commits\?per_page=100 --jq .\[\].sha
```

```diff
 gh api --paginate repos/o/r/pulls/7/commits\?per_page=100 --jq .\[\].sha
+gh repo view <root>/origin.git --json nameWithOwner
```

## dropped_story_usage stderr

```diff
-swarm: dropped-lines: usage: swarm.sh dropped-lines <owner/repo> <n> <40-character head SHA> <base>
+swarm: dropped-lines: usage: swarm.sh dropped-lines [--story <slug>] <owner/repo> <n> <40-character head SHA> <base>
```

## usage stdout

```diff
-#   swarm.sh dropped-lines <owner/repo> <n> <head> <base>  read-only: fetch PR <n>'s head (refs/pull/<n>/head) into the clone of <owner/repo>, check it is <head>, and print each base line a merge on its first-parent chain dropped (`<sha7> <file>: <text>`) that the base still has, at <base> and at the head's merge base with it, and that <head> has not put back, skipping only GitHub's merges of the base that merge recorded as base-merged; exit 0 none, 1 lines dropped, 2 when it cannot check (a moved or stale head, another origin, git below 2.36)
+#   swarm.sh dropped-lines [--story <slug>] <owner/repo> <n> <head> <base>  read-only: fetch PR <n>'s head (refs/pull/<n>/head) into the clone of <owner/repo>, check it is <head>, and print each base line a merge on its first-parent chain dropped (`<sha7> <file>: <text>`) that the base still has, at <base> and at the head's merge base with it, and that <head> has not put back, skipping only GitHub's merges of the base that merge recorded as base-merged, and with --story no line of <slug>'s own story file when <head> deletes it; exit 0 none, 1 lines dropped, 2 when it cannot check (a moved or stale head, another origin, git below 2.36)
```

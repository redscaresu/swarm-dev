---
story: docs-gate-go
pr: 1039
kind: stage
---

# The release docs gate counts the Go tree in the plugin's own repo

#1039 made `merge --release`'s docs gate (release_docs, bin/lib/merge.sh) count `cmd/`, `internal/` and `go.mod` as code beside `bin/`, `commands/` and `hooks/`, in the plugin's own repo.
A release whose only code change since the tag is in the Go tree now needs a doc change or a `Docs: none` line.
The fixture is in tests/diff_fixtures_release_gates.sh.

`merge --release` in the own repo, with only `cmd/x/main.go`, `go.mod` and `internal/guard/x.go` changed since the tag and no doc. Before #1039 the docs gate passed it, and the run stopped at the head's failing check, the next read. Now the docs gate refuses it, naming the three Go paths, before that read.

## gate_release_go_docs stderr

```diff
-swarm: merge: the head 1111111 is not green: test (failure) https://github.com/o/r/runs/test
+swarm: merge: --release: cmd/x/main.go, go.mod, internal/guard/x.go changed since v1.2.0 but README.md, AGENTS.md and docs/ did not: land a docs PR first, or give the PR body a line 'Docs: none — ' and why no doc changes (a '- ' or '* ' bullet before it, or - or -- for the dash, also do; not in a ``` block or a > quote)
```

## gate_release_go_docs files

```diff
-written <root>/fx/1111111111111111111111111111111111111111.checks.n
-written <root>/fx/1111111111111111111111111111111111111111.status.n
```

## gate_release_go_docs file:<root>/gh.log

```diff
-api --paginate repos/redscaresu/swarm-dev/commits/1111111111111111111111111111111111111111/check-runs?per_page=100
-api --paginate repos/redscaresu/swarm-dev/commits/1111111111111111111111111111111111111111/status?per_page=100
```

## gate_release_go_docs file:<root>/proj/.swarm/events.tsv

```diff
-<time>	merge	https://github.com/redscaresu/swarm-dev/pull/7	-	the head 1111111 is not green: test (failure) https://github.com/o/r/runs/test ~~ version=<version>
+<time>	merge	https://github.com/redscaresu/swarm-dev/pull/7	-	--release: cmd/x/main.go, go.mod, internal/guard/x.go changed since v1.2.0 but README.md, AGENTS.md and docs/ did not: land a docs PR first, or give the PR body a line 'Docs: none — ' and why no doc changes (a '- ' or '* ' bullet before it, or - or -- for the dash, also do; not in a ``` block or a > quote) ~~ version=<version>
```

## gate_release_go_docs file:<root>/proj/.swarm/gh-calls.tsv

```diff
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/:id/check-runs	rest	paginate	0
-<time>	-	swarm.sh merge	api repos/redscaresu/swarm-dev/commits/:id/status	rest	paginate	0
```

## gate_release_go_docs calls:fg

```diff
-gh api --paginate repos/redscaresu/swarm-dev/commits/1111111111111111111111111111111111111111/check-runs\?per_page=100
-gh api --paginate repos/redscaresu/swarm-dev/commits/1111111111111111111111111111111111111111/status\?per_page=100
```

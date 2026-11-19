---
kind: code
status: ready
epic: ship-gates
depends_on: []
touches: [bin/lib/board.sh:protected_paths own-repo list, bin/lib/board.sh:pr_hld protected check, bin/lib/merge.sh:protected_hold own-repo paths, bin/lib/merge.sh:merge header comment, bin/swarm.sh:usage merge line, tests/merge_protected_hold_test.sh:own-repo cases, tests/grants_test.sh:own-repo cases, docs/reference-merging.md:protected-path hold (§ Merging), docs/reference-planning.md:grants none sentence (§ Commands), docs/reference-planning.md:protected-path sentence (§ Writing an HLD), docs/method.md:merge policy note]
estimate_lines: 220
risk: high
costs: money
---

# In swarm-dev's own repo, hold a PR that touches the four protected Go packages or .claude-plugin/

Its `costs: money` line holds its PR for the user's merge (see the note below).

This story fixes the four package paths for every later epic: `internal/guard/`, `internal/merge/`,
`internal/release/` and `internal/agentenv/`. Those are the names port-guard, port-merge,
port-release-gates and port-agent-starts already use.

The four, with `.claude-plugin/`, are protected only when the PR's repo is the plugin's own
(plugin_repo, bin/lib/merge.sh:2717). The old list (bin/lib/board.sh:2461) still holds in every repo.

Both callers pass the PR's repo: protected_hold (merge.sh:424) and pr_hld (board.sh:2505).
- Compare the PR's repo with plugin_repo after lower-casing both, as release_upgrade does
  (merge.sh:2654). merge_pr keeps the URL's case (merge.sh:1223-1224), and plugin_repo is lower case
  (merge.sh:2722).
- Match the five paths in any case, as the old list is matched today (the loop at
  tests/merge_protected_hold_test.sh:42 tests `.CLAUDE/` and `Hooks/`).
- Match whole path prefixes with the trailing slash, so `internal/guardian/` is no match.
- When plugin_repo cannot answer, hold the five paths and say so in the hold line (fail closed).
  pr_hld prints only `none`, so there the fail-closed case is `grants` printing `none`.

Reword the comment at merge.sh:415-416: `--release` can now change a protected path, and goes unheld
only because its route skips protected_hold (merge.sh:1279,1315). The usage text at bin/swarm.sh:42
and merge's header comment at merge.sh:1160-1161 state the protected list: add the own-repo paths to
each.

Tests: read the plugin's repo from plugin.json, as merge_rules_test.sh:318 does, never as a literal.
List the five paths literally, one case each, so that removing one goes red. merge_fixture.sh's
compare stub matches any repo (:167), and its `gh repo view` reads ${FX}/origin (:284).
grants_test.sh's stub always names O/R (grants_test.sh:29), so it needs a way to name the plugin's
repo.

Docs, one new sentence each: docs/reference-merging.md (§ Merging, the protected-path hold),
docs/reference-planning.md:44 and :213, and a sentence under docs/method.md's merge-policy table
(:121), not a longer table row. docs/running.md:34,135 describe a user's project, where nothing
changes: leave them, and say so in the PR.

More than two mutation proofs, so use the worktree copy (AGENTS.md). Nothing here holds a live PR
before v0.32.0 is installed, so the review agent does not look for a live hold.


**Why `costs: money`:** this story spends no money. The user chose on 2026-11-19 to hold it for their merge this way, under `merge = agent`, so that the rest of the board keeps merging while they are away. v0.31.3 has no other way to hold one PR in bash files for the user: `swarm.sh merge` holds a `costs: money` PR for the user whatever the merge setting. `flow` will count it as a costly story; that is expected.
**Done when:**
- In tests/merge_protected_hold_test.sh, with the PR in the plugin's own repo and `merge = agent`,
  `swarm.sh merge` holds a story PR that touches each of internal/guard/x.go, internal/merge/x.go,
  internal/release/x.go, internal/agentenv/x.go and .claude-plugin/marketplace.json, one case each,
  with `held: s changes <path>, which only the user merges; the user merges it`
- Each of those five cases goes red when its path is taken out of the list (shown on a worktree
  copy, FAIL lines quoted in the PR)
- An own-repo PR URL written in mixed case (owner and name) holds internal/merge/x.go, and goes
  unheld when the lower-casing is removed (shown on the copy)
- In the own repo, Internal/Merge/x.go and .Claude-Plugin/x.json are held, and go unheld when the
  new paths are matched case-sensitively (shown on the copy)
- With plugin.json's repository unreadable, protected_hold holds internal/merge/x.go with a line
  saying plugin_repo could not answer, and `swarm.sh grants` prints `none` for that PR; with the
  fail-closed branch removed it merges unheld (shown on the copy)
- In the own repo, a PR that touches only internal/guardian/x.go merges unheld
- In o/r, under `merge = agent`, a PR that touches internal/merge/x.go and .claude-plugin/plugin.json
  merges unheld
- In tests/grants_test.sh, `swarm.sh grants` prints `none` for an own-repo story PR that touches
  internal/merge/x.go, and for an o/r story PR that touches it prints its HLD and grants, as today
- Every existing .claude/, .github/, hooks/ and makefile case still passes in o/r
- scripts/select-tests.sh --run passes

---
story: patch-gate-port
pr: 1043
kind: stage
---

# The patch gate passes tests-only and port: true changes in the plugin's own repo

#1043 changed non_fix_change (bin/lib/board.sh) in the plugin's own repo.
A change whose whole diff is under `tests/` is a fix.
A `port: true` story's PR is a fix when every `tests/` file it changes is in the story's touches at the base.
The refusals name `port:`, and merge --release's retro gate pass line names the new fixes.
NON_FIX_RULE=2 is in the non-fix cache file's name, so each fixture's cache file moves from `rule1-` to `rule2-`.
The fixtures are in tests/diff_fixtures_release_gates.sh.

`next`, a story with neither `fix:` nor `port:` that changes `bin/x`: the refusal names both fields now.

## gate_next_neither stdout

```diff
-origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and 1a1fc20 #3 story/s9: docs/stories/s9.md had no fix: true before the merge is no fix, so the release is a minor, and v1.3.0 has no done retro file (no docs/retros/v1.3.0.md at origin/main): open retro-v1-3-0 (kind: lead), then swarm.sh retro --since v1.2.0
+origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and 1a1fc20 #3 story/s9: docs/stories/s9.md had no fix: true or port: true before the merge is no fix, so the release is a minor, and v1.3.0 has no done retro file (no docs/retros/v1.3.0.md at origin/main): open retro-v1-3-0 (kind: lead), then swarm.sh retro --since v1.2.0
```

## gate_next_neither files

```diff
-written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule1-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-1a1fc20228fb2008dad2a44c7121fc59f5fbf1b3.json
+written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-1a1fc20228fb2008dad2a44c7121fc59f5fbf1b3.json
```

## gate_next_neither file:<root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-1a1fc20228fb2008dad2a44c7121fc59f5fbf1b3.json

```diff
^
+"1a1fc20 #3 story/s9: docs/stories/s9.md had no fix: true or port: true before the merge"
\ No newline at end of file
```

`next`, a `port: true` story PR that changes `bin/x` and the one `tests/` file its touches list at the base: a patch now.

## gate_next_port_listed stdout

```diff
-retro v1.3.0
-origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and 43c5404 #3 story/p1: docs/stories/p1.md had no fix: true before the merge is no fix, so the release is a minor, and v1.3.0 has no done retro file (no docs/retros/v1.3.0.md at origin/main): open retro-v1-3-0 (kind: lead), then swarm.sh retro --since v1.2.0
+release
+origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and every one is a fix: cut v1.2.1, a patch
```

## gate_next_port_listed files

```diff
-written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule1-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-43c5404dd8028bd76daea4643be670d5f61c0a95.json
+written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-43c5404dd8028bd76daea4643be670d5f61c0a95.json
```

## gate_next_port_listed file:<root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-43c5404dd8028bd76daea4643be670d5f61c0a95.json

```diff
^
+""
\ No newline at end of file
```

`next`, a `port: true` story PR that adds `tests/b_test.sh` to its own story's touches: the base's touches count, so it is refused, naming the file.

## gate_next_port_self_listed stdout

```diff
-origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and cd2f16e #3 story/p3: docs/stories/p3.md had no fix: true before the merge is no fix, so the release is a minor, and v1.3.0 has no done retro file (no docs/retros/v1.3.0.md at origin/main): open retro-v1-3-0 (kind: lead), then swarm.sh retro --since v1.2.0
+origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and cd2f16e #3 story/p3: port: true, but it changes tests/b_test.sh, not in docs/stories/p3.md's touches before the merge is no fix, so the release is a minor, and v1.3.0 has no done retro file (no docs/retros/v1.3.0.md at origin/main): open retro-v1-3-0 (kind: lead), then swarm.sh retro --since v1.2.0
```

## gate_next_port_self_listed files

```diff
-written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule1-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-cd2f16e55c33cb155bf4b2fc7d88a7018c9e00fd.json
+written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-cd2f16e55c33cb155bf4b2fc7d88a7018c9e00fd.json
```

## gate_next_port_self_listed file:<root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-cd2f16e55c33cb155bf4b2fc7d88a7018c9e00fd.json

```diff
^
+"cd2f16e #3 story/p3: port: true, but it changes tests/b_test.sh, not in docs/stories/p3.md's touches before the merge"
\ No newline at end of file
```

`next`, a `port: true` story PR that changes `tests/b_test.sh`, which its touches do not list: refused, naming the file.

## gate_next_port_unlisted stdout

```diff
-origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and 48fead4 #3 story/p2: docs/stories/p2.md had no fix: true before the merge is no fix, so the release is a minor, and v1.3.0 has no done retro file (no docs/retros/v1.3.0.md at origin/main): open retro-v1-3-0 (kind: lead), then swarm.sh retro --since v1.2.0
+origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and 48fead4 #3 story/p2: port: true, but it changes tests/b_test.sh, not in docs/stories/p2.md's touches before the merge is no fix, so the release is a minor, and v1.3.0 has no done retro file (no docs/retros/v1.3.0.md at origin/main): open retro-v1-3-0 (kind: lead), then swarm.sh retro --since v1.2.0
```

## gate_next_port_unlisted files

```diff
-written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule1-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-48fead416e3a08c5085560ff88cf264034978fb0.json
+written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-48fead416e3a08c5085560ff88cf264034978fb0.json
```

## gate_next_port_unlisted file:<root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-48fead416e3a08c5085560ff88cf264034978fb0.json

```diff
^
+"48fead4 #3 story/p2: port: true, but it changes tests/b_test.sh, not in docs/stories/p2.md's touches before the merge"
\ No newline at end of file
```

`next`, `port: x`: refused, naming the value.

## gate_next_port_x stdout

```diff
-origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and 2182e4e #3 story/p8: docs/stories/p8.md had no fix: true before the merge is no fix, so the release is a minor, and v1.3.0 has no done retro file (no docs/retros/v1.3.0.md at origin/main): open retro-v1-3-0 (kind: lead), then swarm.sh retro --since v1.2.0
+origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and 2182e4e #3 story/p8: docs/stories/p8.md had port: x before the merge, not true is no fix, so the release is a minor, and v1.3.0 has no done retro file (no docs/retros/v1.3.0.md at origin/main): open retro-v1-3-0 (kind: lead), then swarm.sh retro --since v1.2.0
```

## gate_next_port_x files

```diff
-written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule1-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-2182e4e4b61068797c9c4f3fbc76981c3e33f3dc.json
+written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-2182e4e4b61068797c9c4f3fbc76981c3e33f3dc.json
```

## gate_next_port_x file:<root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-2182e4e4b61068797c9c4f3fbc76981c3e33f3dc.json

```diff
^
+"2182e4e #3 story/p8: docs/stories/p8.md had port: x before the merge, not true"
\ No newline at end of file
```

`next`, a story PR with neither field whose whole diff is under `tests/` once its story file is gone: a patch now.

## gate_next_tests_only stdout

```diff
-retro v1.3.0
-origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and c2674f2 #3 story/t1: docs/stories/t1.md had no fix: true before the merge is no fix, so the release is a minor, and v1.3.0 has no done retro file (no docs/retros/v1.3.0.md at origin/main): open retro-v1-3-0 (kind: lead), then swarm.sh retro --since v1.2.0
+release
+origin/main has 1 commit(s) since v1.2.0 that change files outside the board, and every one is a fix: cut v1.2.1, a patch
```

## gate_next_tests_only files

```diff
-written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule1-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-c2674f22d1cb9ed19c591beac1ac34373a0efab7.json
+written <root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-c2674f22d1cb9ed19c591beac1ac34373a0efab7.json
```

## gate_next_tests_only file:<root>/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-e88c59af8c8a3409da3ec9c2d381cb061a813e15-c2674f22d1cb9ed19c591beac1ac34373a0efab7.json

```diff
^
+""
\ No newline at end of file
```

`merge --release` of a patch, a `port: true` story PR whose `tests/` files its touches all list: the retro gate passes, and its pass line names `port: true` stories and tests-only changes. The docs gate after it refuses the release (`bin/f.sh` changed and no doc did), so the run reads the PR's body and stops there.

## gate_release_port_listed stdout

```diff
^
+retro gate: v1.2.1 is a patch; every change since v1.2.0 is from a fix: true or port: true story, a fix-main build or a change only under tests/
```

## gate_release_port_listed stderr

```diff
-swarm: merge: --release: v1.2.1 is a patch, but 833649a #9 story/port-a: docs/stories/port-a.md had no fix: true before the merge: cut a minor after its retro
+swarm: merge: --release: bin/f.sh changed since v1.2.0 but README.md, AGENTS.md and docs/ did not: land a docs PR first, or give the PR body a line 'Docs: none — ' and why no doc changes (a '- ' or '* ' bullet before it, or - or -- for the dash, also do; not in a ``` block or a > quote)
```

## gate_release_port_listed files

```diff
-written <root>/proj/.swarm/gh-cache/redscaresu--swarm-dev/non-fix/rule1-docs%2F-ff8fbfb71dd67b492c72cfde8d75a2a1cd30e714-833649a5d23def4a870eace63d3aded860a4c5e5.json
+written <root>/proj/.swarm/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-ff8fbfb71dd67b492c72cfde8d75a2a1cd30e714-833649a5d23def4a870eace63d3aded860a4c5e5.json
```

## gate_release_port_listed file:<root>/gh.log

```diff
 pr list --repo redscaresu/swarm-dev --state merged --search merged:>=2026-10-31 --json number,headRefName,mergeCommit --limit 1000
+pr view 7 --repo redscaresu/swarm-dev --json body
```

## gate_release_port_listed file:<root>/proj/.swarm/events.tsv

```diff
-<time>	merge	https://github.com/redscaresu/swarm-dev/pull/7	-	--release: v1.2.1 is a patch, but 833649a #9 story/port-a: docs/stories/port-a.md had no fix: true before the merge: cut a minor after its retro ~~ version=<version>
+<time>	merge	https://github.com/redscaresu/swarm-dev/pull/7	-	--release: bin/f.sh changed since v1.2.0 but README.md, AGENTS.md and docs/ did not: land a docs PR first, or give the PR body a line 'Docs: none — ' and why no doc changes (a '- ' or '* ' bullet before it, or - or -- for the dash, also do; not in a ``` block or a > quote) ~~ version=<version>
```

## gate_release_port_listed file:<root>/proj/.swarm/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-ff8fbfb71dd67b492c72cfde8d75a2a1cd30e714-833649a5d23def4a870eace63d3aded860a4c5e5.json

```diff
^
+""
\ No newline at end of file
```

## gate_release_port_listed file:<root>/proj/.swarm/gh-calls.tsv

```diff
 <time>	-	swarm.sh merge	pr list	graphql	-	0
+<time>	-	swarm.sh merge	pr view	graphql	-	0
```

## gate_release_port_listed calls:fg

```diff
 gh pr list --repo redscaresu/swarm-dev --state merged --search merged:\>=2026-10-31 --json number\,headRefName\,mergeCommit --limit 1000
+gh pr view 7 --repo redscaresu/swarm-dev --json body
```

`merge --release` of a patch, a `port: true` story PR that changes `tests/b_test.sh`, which its touches do not list: still refused by the retro gate, in the new words.

## gate_release_port_unlisted stderr

```diff
-swarm: merge: --release: v1.2.1 is a patch, but abd5c1f #9 story/port-a: docs/stories/port-a.md had no fix: true before the merge: cut a minor after its retro
+swarm: merge: --release: v1.2.1 is a patch, but abd5c1f #9 story/port-a: port: true, but it changes tests/b_test.sh, not in docs/stories/port-a.md's touches before the merge: cut a minor after its retro
```

## gate_release_port_unlisted files

```diff
-written <root>/proj/.swarm/gh-cache/redscaresu--swarm-dev/non-fix/rule1-docs%2F-b11528ce870dc063a3aed88f0190e3ee2eaf6315-abd5c1fabe59cc3866c1f52a51fbdcf8f6752ee2.json
+written <root>/proj/.swarm/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-b11528ce870dc063a3aed88f0190e3ee2eaf6315-abd5c1fabe59cc3866c1f52a51fbdcf8f6752ee2.json
```

## gate_release_port_unlisted file:<root>/proj/.swarm/events.tsv

```diff
-<time>	merge	https://github.com/redscaresu/swarm-dev/pull/7	-	--release: v1.2.1 is a patch, but abd5c1f #9 story/port-a: docs/stories/port-a.md had no fix: true before the merge: cut a minor after its retro ~~ version=<version>
+<time>	merge	https://github.com/redscaresu/swarm-dev/pull/7	-	--release: v1.2.1 is a patch, but abd5c1f #9 story/port-a: port: true, but it changes tests/b_test.sh, not in docs/stories/port-a.md's touches before the merge: cut a minor after its retro ~~ version=<version>
```

## gate_release_port_unlisted file:<root>/proj/.swarm/gh-cache/redscaresu--swarm-dev/non-fix/rule2-docs%2F-b11528ce870dc063a3aed88f0190e3ee2eaf6315-abd5c1fabe59cc3866c1f52a51fbdcf8f6752ee2.json

```diff
^
+"abd5c1f #9 story/port-a: port: true, but it changes tests/b_test.sh, not in docs/stories/port-a.md's touches before the merge"
\ No newline at end of file
```

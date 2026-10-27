---
kind: code
status: ready
epic: merge-holds
depends_on: []
touches: [bin/lib/board.sh:protected_paths (new), bin/lib/board.sh:pr_hld protected-path line, bin/lib/merge.sh:merge_hold, bin/lib/merge.sh:merge_pr header comment, bin/swarm.sh:merge usage line, docs/reference.md:Merging protected-path hold, docs/reference.md:grants paragraph, README.md:merge = agent lines, tests/merge_protected_hold_test.sh (new)]
estimate_lines: 210
easy: false
risk: high
---

# Under merge = agent, swarm.sh merge holds a story PR that changes a protected path for the user

The epic's line numbers are stale at 31ead5b, so find the code by function name.
- Move pr_hld's protected-path pattern (bin/lib/board.sh:1149) into one helper, `protected_paths`, in board.sh beside pr_hld. It reads paths on stdin and prints those under .claude/, .github/ or hooks/, and a root Makefile, GNUmakefile or makefile. pr_hld calls it, and its pattern does not change (the epic's Out of scope).
- merge_hold (bin/lib/merge.sh:187-192): under merge = agent, on the story route only, list the PR's files at the pin after pr_held's money check. --board is limited to board paths and --release to plugin.json (merge.sh:282-290), and neither can be protected. Read them with `ci_gate files-status <repo> <n> <changed> <base> <head>`, which compares <base>...<head> as pr_hld does (board.sh:1145-1148), so a push after the pin cannot hide a path.
- That list has each renamed file's old path too (pr_files, ci_gate.py:446-470), so renaming a file out of hooks/ also holds. merge_hold reads merge_pr's locals, as merge_read does (merge.sh:141). Keep it under 4 parameters.
- When a file is protected, refuse with `held: <slug> changes <path>, which only the user merges; the user merges it`. A file list it cannot read also holds, saying so (fail closed, as pr_held does). The event is `merge <slug> held: ...`. Keep the `held: ... the user merges it` shape. The conductor's rule keys on it (bin/lib/build.sh:173-175), and that brief text belongs to conductor-hands-off and review-loop, so this story leaves it alone.
- Under merge = human it reads no files. merge_grant already refuses these PRs, because pr_hld puts them under no HLD (merge.sh:302-306).
- Docs: merge_pr's header comment (merge.sh:211-229) and the merge line of swarm.sh's usage header name the hold. docs/reference.md § Merging (:1883) gets the hold and its exit: the user merges the PR by hand, and the next reconcile finishes the story. No per-PR lift exists (see contradictions). reference.md's grants paragraph (:391) and README.md's merge = agent lines (:51, :131) say a protected-path PR waits for the user under either merge mode. AGENTS.md's merge bullet lists no holds today, so it stays as it is. AGENTS.md is wait-pr-new-head's.
- The new test file uses small fixtures and stays out of SLOW (Makefile:20-26). If it must join SLOW, this PR edits the Makefile, a protected path, and ci.yml's shard count (tests/test_shard_test.sh), so the PR waits for the user's merge. Say so in the PR.
- Order across epics, where another story edits the same part:
  - board.sh:pr_hld: less-noise's contents-reader and board-root-helper.
  - merge.sh:merge_pr: less-noise's board-root-helper, conductor-hands-off's story-merge-notes-conductor and fixes-027's epic-guard-story-merge.
  - reference.md § Merging: review-loop's merge-from-review-pane.
  If any of them is open alongside this one, this merges first: here pr_hld changes one line, merge_pr only its header comment and § Merging one paragraph.
- This PR touches no protected path. On this board the hold takes effect once the lead's installed plugin includes it, after the v0.29.0 release.

**Done when:**
- tests/merge_protected_hold_test.sh (new, merge_fixture.sh's gh stub, merge = agent) has a case each for a story PR changing hooks/x.sh, .github/workflows/ci.yml, .claude/settings.json and a root Makefile. In each, swarm.sh merge exits non-zero and prints `held: <slug> changes <that path>`. gh.log shows no `pr merge`, and events.tsv has a `merge <slug> held:` line.
- Same file: a PR that renames hooks/x.sh to bin/x.sh (status renamed, previous_filename hooks/x.sh in the pinned compare) is held, naming hooks/x.sh.
- In the same file, a story PR changing only bin/x.sh and its story file merges (gh.log shows `pr merge`). PRs changing sub/Makefile or docs/hooks/x.md also merge: the pattern is anchored at the root.
- Same file: when the compare read of the PR's files at the pin fails, the PR is held and the message says its files could not be read. When the PR's files API lists a harmless set for a later head while the pinned head adds hooks/x.sh, the PR is held.
- Same file, merge = human with an HLD granting merge: a PR changing hooks/x.sh is still refused, with merge_grant's message, as today.
- The PR body says the four path cases and the rename case failed when the merge_hold arm was removed in a copy of the checkout.
- tests/grants_test.sh and tests/grant_pinned_head_test.sh pass unchanged: the grant lookup still says none for these paths.
- reference.md § Merging, its grants paragraph, README.md and swarm.sh's merge usage line name the hold and the user's exit.

---
kind: code
status: ready
epic: retro-report
depends_on: []
touches: [bin/lib/merge.sh:board_paths, bin/lib/merge.sh:on_board_paths, bin/lib/ci_gate.py:board-path matcher (behind and fixed), templates/ci/board-only.sh:path case, templates/pre-commit:path case, tests/init_test.sh:gate and pre-commit retros cases, tests/merge_board_root_test.sh:--board retros paths, tests/merge_base_moved_test.sh:board-path matcher case, tests/board_pr_test.sh:board_dir = . refusal, docs/method.md:init's board-only gate sentence (§ Configuring a project; :101-102), docs/reference-merging.md:paths the --release docs check ignores (§ Merging; :198-199), docs/reference-merging.md:A base that moved (its board paths sentence; :264-268), docs/reference-merging.md:Releases board-path list]
estimate_lines: 170
easy: false
risk: high
---

# retros/*.md counts among the board's own files, so a retro file PR is board-only

Add `retros/*.md` (not the whole of retros/) to the board's own paths, so a retro file PR is board-only and a script under retros/ is not. It is a new kind of entry, a glob. Every reader of the list has to match it the same way: board_paths (bin/lib/merge.sh:2020-2027) gains `${rel}retros/*.md`. on_board_paths (:2029-2038) matches an entry holding `*` as a glob, with its loose-match note. ci_gate.py's behind (:189) and fixed (:833) share one matcher that does the same with fnmatch. fixed's startswith today would never match a glob, so the matcher replaces it. templates/ci/board-only.sh:13 and templates/pre-commit:6 each gain `"${BOARD}"retros/*.md` in their case line. The pre-commit file is the fourth copy, written by init_hook (bin/lib/lifecycle.sh:2073-2080). Without this change, in a user project a retro file PR runs full CI and a retro-only commit runs make check. At a root board (board_dir = .), merge --board refuses the PR (merge.sh:1156-1157). swarm-dev's own scripts/board-only.sh already counts every board/ path (:5-8). The other callers read board_paths and need no code change. The PR body names each one and says why the glob is safe there: release_due's excludes (bin/lib/board.sh:1219) and release_docs' excludes (merge.sh:2808) are git pathspecs, which match globs by default. merge.sh:505 (base_moved, through behind) and lifecycle.sh:3410 and merge.sh:2060 (through fixed) use the shared matcher. in_board (merge.sh:2042-2047) uses on_board_paths. merge --board's message (merge.sh:1157) and board-pr's refusal text (lifecycle.sh:156) only print the list. Leave dash_finished.py's BOARD_OWN (:32), dash.sh:460 and docs/dash.md:172 alone. Today a commit that deletes a story file and adds retros/v0.31.0.md counts as the story's own work (dash_finished.py:42-43), so dash shows the retro story finished, which is right. Update the docs that list the paths: docs/method.md:101-102, and docs/reference-merging.md:198-199 and :264-268. Also say that init writes an existing project's .github/swarm-board-only.sh and pre-commit hook only when they are absent (lifecycle.sh:2066-2080). Such a project keeps the old list until the user deletes the files and runs init. This is CI's skip gate. Change only the path lists and their matching, and keep every other case of the gate as it is. Open PR #862 edits tests/board_pr_test.sh. Rebase on it if it has merged.

With board_dir = . the glob also changes release_due: a retro-only commit no longer makes a release due. docs/reference-merging.md § Releases lists the board's paths (about :924-925); add retros/*.md there.

**Done when:**
- docs/reference-merging.md § Releases names retros/*.md among the board's paths, and a release_due case shows a retro-only commit at a root board makes no release due.
- tests/init_test.sh, the gate init writes: board_only=true for a PR that adds only <board>/retros/v1.0.0.md, board_only=false for one that adds only <board>/retros/x.sh, and board_only=false for retros/v1.0.0.md beside bin/x.
- tests/init_test.sh, the pre-commit hook init writes: a commit of only <board>/retros/v1.0.0.md skips make check, and a commit of <board>/retros/x.sh runs it (a Makefile check target that writes a marker shows which).
- tests/merge_board_root_test.sh: at board_dir = ., merge --board accepts a PR that changes only retros/v1.0.0.md, and refuses one that changes retros/x.sh or bin/tool.
- A case in tests/merge_base_moved_test.sh calls ci_gate.py's shared matcher directly (python3 -I with bin/lib on sys.path). It shows retros/v1.0.0.md on the board's paths and retros/x.sh and Board.base.py off them, for the matcher behind and fixed use.
- tests/board_pr_test.sh's board_dir = . refusal (:599) names retros/*.md among the paths. The new cases fail on a worktree copy without the retros entry in board_paths and the two templates, and the PR body has the FAIL lines.
- tests/loose_match_test.sh, tests/doc_check_test.sh and shellcheck pass. The PR body names each other board_paths caller with why the glob is safe there, and says the humanizer ran over the changed docs.

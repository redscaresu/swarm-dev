---
kind: code
status: ready
epic: rules-file
depends_on: []
touches: [bin/lib/build.sh:build_story, tests/board_state_test.sh:story refusal cases, docs/reference.md:Board state]
estimate_lines: 100
easy: false
---

# story refuses a story whose file has edits origin does not have

Needs nothing from another story. This is Appendix B's item: a rebuilt story's From review items sit uncommitted in the main checkout, so a builder reading its worktree's copy misses them (0.28 HLD:779-780). swarm.sh keeps its own writes out of tracked story files (board-state, docs/reference.md:1138-1142), so an uncommitted change to a story file in the main checkout is a person's edit. In build_story (bin/lib/build.sh:541), before the worktree is made (beside require_trusted), act only when story_path (build.sh:338-345) gives the worktree-relative copy: board in the repo, story in the project's own repo, tracked. Refuse when the story file has uncommitted changes in the main checkout, or local commits that origin/<base> lacks. The message names the file and the fix: land the edit with swarm.sh board-pr (or push it), then start the story again. A main checkout that is only behind origin is not refused. A story whose repo: names a sibling repo, or an untracked one (fix_main's), reads the board's own copy and is not checked; a story whose repo: names the project's own repo (repo_dir gives PROJECT_DIR, and story_path the worktree-relative copy) is checked like one with no repo:. Name the refusal in docs/reference.md's Board state paragraph. It runs on every build's start path, so a false refusal stops every conductor's builds: test the pass cases as hard as the refusals.

**Done when:**
- In tests/board_state_test.sh, on a board in the repo, `swarm.sh story <slug>` with an uncommitted edit to the story's body in the main checkout exits non-zero, names the file and swarm.sh board-pr, and leaves no worktree or story/<slug> branch. The same story with no local edit starts.
- A story whose file has a local commit that origin/<base> lacks is refused the same way. A main checkout behind origin/<base> with no local edit is not refused.
- With the check removed, the refusal test goes red; its FAIL line is in the PR body.
- docs/reference.md's Board state paragraph names the refusal.
- A story whose `repo:` names a sibling repo, and an untracked story (fix_main's), start with a local edit present; one whose `repo:` names the project's own repo is refused; a story file with a staged, uncommitted edit is refused like an unstaged one.

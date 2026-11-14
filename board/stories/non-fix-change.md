---
kind: code
status: ready
epic: retro-gate
depends_on: []
touches: [bin/lib/board.sh:non_fix_change (new), tests/non_fix_test.sh]
estimate_lines: 260
easy: false
risk: high
---

# non_fix_change lists each change since a commit that no fix: true story or fix-main build made

The one definition of a fix, for next and merge --release. No record says a change is a fix today. Story kinds are code|docs|chore|lead (templates/docs/stories/README.md:12). fix-main stories are written kind: code (bin/lib/merge.sh:1865) and are git-ignored. A story walk misses storyless commits, though release_due counts every non-board commit (bin/lib/board.sh:1208-1220). Add non_fix_change <repo> <from> <ref> to bin/lib/board.sh beside release_stage. <from> is a commit: merge --release passes origin's tag SHA, next the local tag's. <ref> is a commit or ref. A change is each first-parent commit in <from>..<ref> that touches a file outside the board (release_due's pathspec, through git rev-list). Use no git log: next_test counts git log calls (:969-980). A change's PR is the merged PR whose mergeCommit is that commit, from one paginated gh pr list --repo <repo> --state merged --json number,headRefName,mergeCommit --limit 1000, searched from the day before <from>'s commit date. A change is a fix only when its PR's head is story/fix-main-* (a fix-main build), or story/<slug> whose stories/<slug>.md has fix: true exactly. Read that file at the commit, or at its parent when the commit deleted it. Strip a trailing # comment and spaces first, as stage_of does. Every other change prints one line: '<sha7> #<n> <head>: <why>' or '<sha7>: no merged PR has this commit'. That covers a story with no fix: true (fix: yes too), a story file missing at the commit, any other branch (a lead PR, dependabot, a hand fix), a direct push, and a rebase-merged PR's earlier commits. It reads git only at those commits, never the checkout or the board's state. So a local edit, or a story still on the board at done, changes nothing, and a story merged before <from> is outside the window whatever its status. It prints nothing when every change is a fix. It exits 1, with why on stderr, when git cannot read <from> or <ref>, when gh fails, or when the board is outside the repo (git holds no story history then). Callers count exit 1 as a non-fix change. Cache the answer through bin/lib/gh_cache.py (SWARM_GH_CACHE=<project>/.swarm/gh-cache), keyed by the two SHAs, written only once git and gh both answered. A merged commit's PR and a story's text at a commit never change, so next, which dash runs every frame, pays one gh call per base move. SWARM_GH_FRESH=1 skips the cached read. Nothing calls it in this PR. bash 3.2; avoid removed_test's banned names (:21, :60).

The check must also hold these rules:
- Match fix-main heads exactly: `^story/fix-main-[0-9a-f]{7}$` (merge.sh writes only fix-main-<sha7>, bin/lib/merge.sh:1821). Never a `story/fix-main-*` prefix: a planner slug such as fix-main-docs would pass as a fix.
- Read the story file only at `<commit>^`, the base as the planner left it, so a PR cannot mark its own feature a fix by adding `fix: true` in its own diff.
- Read `fix:` only from the first front-matter block (fm_text, bin/lib/board.sh:1342-1345), never from the body.
- Walk the commits with `--full-history` beside `--first-parent`, so a --no-ff merge commit that is TREESAME to its second parent is still checked.
- Cache only an answer with no `no merged PR has this commit` line (gh's search index can lag a fresh merge), and put a rule version in the cache file's name.

**Done when:**
- tests/non_fix_test.sh (new), on a git fixture tagged v1.2.0 with a stub gh that lists merged PRs: a commit from story/s1, whose s1 has fix: true at that commit, is not printed. Commits from story/s2 (no fix: line), story/s3 (fix: yes) and fix/x, and a commit no PR lists, are each printed with their sha7. A commit from story/fix-main-abc1234, which has no story file, is not printed. A board-only commit is not read.
- Same test: a story PR that deleted its own file is read at the commit's parent. A non-fix story merged before the tag, still on the board at done, plus a fix: true story after it, prints nothing. Adding fix: true to s2 in the checkout, or setting its state to done, changes nothing. With <from> set to a commit after s2's, s2 is not printed while the local tag still points before it.
- Same test: an invalid <ref>, a failing gh and a board outside the repo each exit 1. A second run on the same SHAs with gh failing prints the first run's answer from the cache; with SWARM_GH_FRESH=1 it exits 1.
- The test fails on a worktree copy with the fix: true match removed, and again with the no-PR line skipped. The PR body has the FAIL lines.
- A story/fix-main-docs decoy branch is printed as a non-fix; story/fix-main-<sha7> is a fix
- A PR that adds `fix: true` to its own story file is printed as a non-fix
- `fix: true` only in a story's body is printed as a non-fix
- A --no-ff merge commit from a non-fix story is printed
- A run whose gh call fails first leaves no cache file, and the next run gives the real answer
- Each of these five cases goes red with its rule removed, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)

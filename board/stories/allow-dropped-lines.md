---
kind: code
status: blocked
epic: port-checks
depends_on: [allow-list]
needs: allow-list (the entry format, --only and --draft)
touches: [scripts/allow/stage-1/dropped-lines-own-story-file.md, tests/diff_fixtures_dropped.sh]
estimate_lines: 160
---

# Stage 1's allow list names the dropped-lines fix

Uses allow-list's format, --only and --draft. The entry is for dropped-lines-own-story-file, #1021, kind fix; its fix: true comes from the file at 198ceef9, since the PR deleted that file. Fixtures in tests/diff_fixtures_dropped.sh cover each output #1021 changed: the dropped-lines usage line (bin/swarm.sh, on the seed usage fixture); `dropped-lines --story`, a usage error on v0.31.2; the scan skipping the story's own file; and merge's story route on a PR with a base-merge commit. On that route dropped_hold passes --story (bin/lib/merge.sh:1058), and dropped_lines' origin_repo adds a gh repo view (bin/lib/merge.sh:390-397). The board is in the repo and the stub names origin to match, so the --own path runs.

**Done when:**
- (1) `tests/diff_run.sh --stage 1 --only dropped-lines-own-story-file`, v0.31.2's tree against v0.31.3's (#1021 and the version bump only), exits 0 over every fixture on main. The PR quotes it. (2) On a worktree copy without .git, deleting any one hunk makes (1) red, naming its fixture, the gh repo view hunk included. (3) `--stage 1`, v0.31.2 against main, over every fixture on main: each difference is covered, or the PR names the open allow-* story of this epic that covers it. The last of allow-dropped-lines, allow-go-paths and allow-release-gates to merge quotes that run exiting 0.
- scripts/select-tests.sh --run passes

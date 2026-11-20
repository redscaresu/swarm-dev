---
kind: code
status: blocked
epic: port-checks
depends_on: [allow-list, protected-go-paths]
needs: allow-list (the entry format, --only and --draft); protected-go-paths (the merged holds its entry cites)
touches: [scripts/allow/stage-1/protected-go-paths.md, tests/diff_fixtures_go_paths.sh]
estimate_lines: 200
---

# Stage 1's allow list names protected-go-paths' new holds

Uses allow-list's format, --only and --draft, and the merged protected-go-paths. The new holds fire only in the plugin's own repo (plugin_repo, from plugin.json), and fresh() names o/r (tests/merge_fixture.sh:284), so the fixtures in tests/diff_fixtures_go_paths.sh name the plugin's repo. They cover, under merge = agent, a story PR touching each of internal/guard/, internal/merge/, internal/release/, internal/agentenv/ and .claude-plugin/ (its held: line and merge event line), `grants` on one such PR, and the usage merge line on the seed usage fixture. One stage entry, written from --draft, cites the PR and the exact lines on each stream and file.

**Done when:**
- (1) `--stage 1 --only protected-go-paths`, its merge commit's parent against the merge commit, exits 0 over every fixture on main. The PR quotes it. (2) On a worktree copy without .git, deleting any one hunk is red, naming its fixture. (3) Every gh call its fixtures make is answered by the stubs: the run shows no shim refusal line. (4) As in allow-dropped-lines (3), the stage-wide run's differences are each covered or named, and the last of the three allow-* stories to merge quotes it exiting 0.
- scripts/select-tests.sh --run passes

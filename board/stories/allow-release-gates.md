---
kind: code
status: blocked
epic: port-checks
depends_on: [allow-list, docs-gate-go, patch-gate-port]
needs: allow-list (the entry format, --only and --draft); docs-gate-go and patch-gate-port (the merged lines their entries cite)
touches: [scripts/allow/stage-1/docs-gate-go.md, scripts/allow/stage-1/patch-gate-port.md, tests/diff_fixtures_release_gates.sh]
estimate_lines: 280
---

# Stage 1's allow list names the docs gate's and the patch gate's new lines

Uses allow-list's format, --only and --draft, and the merged docs-gate-go and patch-gate-port. The fixtures in tests/diff_fixtures_release_gates.sh name the plugin's repo, as allow-go-paths' do. docs-gate-go: `merge --release` on a Go-tree-only change with no doc, refused naming cmd, internal or go.mod. patch-gate-port, through next and `merge --release`: a tests-only change passes; a port: true story with listed tests passes; a port: true story with an unlisted tests/ file is refused; a PR that adds a tests/ file to its own story's list is refused; a story with neither fix: nor port: is refused in the new words; port: x is refused; the release_retro pass line; and the cache file named by the NON_FIX_RULE=2 key (board/stories/patch-gate-port.md:37-45). One entry per story, each citing its PR and the exact lines.

**Done when:**
- (1) `--only docs-gate-go`, its merge commit's parent against the merge commit, and `--only patch-gate-port` on its own pair, each exit 0 over every fixture on main. The PR quotes both. (2) On a worktree copy without .git, deleting any one hunk of either entry is red, naming its fixture. (3) Every gh call its fixtures make is answered by the stubs. (4) As in allow-dropped-lines (3), the stage-wide run's differences are each covered or named, and the last of the three allow-* stories to merge quotes it exiting 0.
- scripts/select-tests.sh --run passes

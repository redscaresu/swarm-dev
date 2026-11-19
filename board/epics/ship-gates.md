---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: []
stage: v0.32.0
---

# Before any Go lands, the merge holds and the release gates know the Go tree, and the user merges the three PRs that teach them

From v0.32.0, in swarm-dev's own repo, a PR that touches the Go package for the guard, merge, the release gates or the agents' environment, or `.claude-plugin/`, is held for the user. The docs gate counts the Go tree. The patch gate passes a tests-only PR and a `port: true` story's PR.

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** (1) On a fixture of the plugin's own repo, `swarm.sh merge` under merge = agent holds a story PR that touches each of the four Go package paths and `.claude-plugin/`, one case per path, and each case fails when its path is taken out of the list. In another project's repo a PR that touches `internal/merge/` is not held, and `grants` still puts it under its HLD. (2) `merge --release` refuses a bump when only the Go tree changed and no doc did, passes it with a doc change, and passes it with a `Docs: none` line. (3) The patch gate passes a PR whose whole diff is under tests/; passes a `port: true` story's PR whose tests/ changes are all files its story lists; refuses a `port: true` PR that changes one unlisted tests/ file; refuses a PR that adds a tests/ file to its own story's list; refuses a story with neither fix: nor port:; and still passes a `fix: true` story and a fix-main build. An answer cached under the old rule version is not read. (4) The user merged both PRs, each handed over by its review agent under merge = human.

**Out of scope:**
- Any Go code
- Porting the gates to Go (port-release-gates, port-merge, port-release)
- Enforcing the freeze in code (HLD:347)
- Holding Go paths in other projects' repos

**Constraints:**
- stage: v0.32.0. The protected-paths story is the first story of the whole plan, and every other epic depends on this one, directly or through another (HLD:295).
- The swarm runs the installed v0.31.2 until v0.32.0 is installed, so nothing this epic changes can hold a stage 1 PR. These three PRs are held by v0.31.2's own rule: with merge = human and no merge grant, `swarm.sh merge` refuses and the review agent hands the PR to the user (bin/lib/merge.sh:415-417; .claude/swarm/config:6). No dependent epic starts before both are merged and merge = agent is back. This resolves contradiction 6.
- The new paths hold only in the plugin's own repo (plugin_repo, bin/lib/merge.sh:2698). protected_paths' one regex holds its paths in every repo the plugin runs on, and pr_hld reads the same list (bin/lib/board.sh:2455-2464,2505), so adding to it would change other boards.
- The first story fixes the four package paths (for example internal/guard, internal/merge, internal/release, internal/agentenv) and names cmd/, internal/ and go.mod for the docs gate. Later epics may not move them. The guard's parser, the environment allowlist, the gates and merge's decisions must live under them; go-layers checks their imports.
- The gate reads `port:` and the tests/ entries of the story's touches at the base the PR merged onto, as it reads `fix:` today (bin/lib/board.sh:1558-1572), never from the PR's own commits or the checkout.
- Both stories edit bash: protected_paths at bin/lib/board.sh:2461, release_docs at bin/lib/merge.sh:3005, non_fix_change at bin/lib/board.sh:1586 with rule=1 at :1590 bumped.
- After this epic's first merge the patch gate refuses every patch until v0.32.0, since the stage 1 stories are no fixes (bin/lib/board.sh:1586). A loop fix found during stage 1 waits for v0.32.0, by decision.
- `port: true` is a new story field. Document it as its own list item in templates/docs/stories/README.md and board/stories/README.md, which must stay byte-identical (tests/board_readme_test.sh:25-47), and in docs/reference-merging.md's patch rule.
- Tests drive swarm.sh from outside, and each is shown to fail (rules.md:25).

**Your part:**
- Lead: cut the last v0.31.x patch before the first PR merges, with the dropped-lines fix in it (story dropped-lines-own-story-file, outside this plan; HLD:76-78). None can ship after that merge until v0.32.0, and the swarm runs the installed version, so a fix that misses the patch holds stage 1's PRs falsely until then.
- Changed on 2026-11-19, the user's choice: the three code stories carry `costs: money`, so `swarm.sh merge` holds each for the user under merge = agent, and the rest of the board keeps merging. The merge = human window (#1024) was opened, then closed again the same day. Earlier plan: once the epic's board PR has merged and before its first build starts, set merge = human in .claude/swarm/config; set it back to agent once all three code PRs are merged. .claude/ is a protected path, so you merge those two small PRs too. PRs of the old active epics also wait on you meanwhile.
- You merge the three code PRs (HLD:297-298): protected-go-paths, docs-gate-go and patch-gate-port. The release gates were split in two so that each PR changes one behaviour.
- Carve-out (HLD:480-485): all three code stories are listed, since they change merge's holds and the release gates. You clear them on the board PR.

**Areas:**
- bin/lib/board.sh (protected_paths, pr_hld, non_fix_change)
- bin/lib/merge.sh (protected_hold, release_docs)
- .claude/swarm/config (merge)
- tests/
- templates/docs/stories/README.md
- board/stories/README.md
- docs/reference-merging.md

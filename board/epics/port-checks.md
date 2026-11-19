---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [ship-gates]
stage: v0.32.0
---

# Goals 2 and 7

The three harnesses every port runs exist before the first port: the differential run, the CI speed fixture and the python3-fails harness.

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** (1) The differential run compares two trees on the same fixtures and stubs for stdout, stderr, exit code, files written and stub calls. It goes red on a seeded one-byte output change, a changed exit code, an extra file and an extra gh call. (2) It takes hooks too: the fixture is the hook's JSON on stdin, and the run compares exit code, stdout, stderr, event lines and herdr and gh stub calls. (3) Stub calls are compared in order on a command's foreground path and in order within each background step, and a bash-against-bash run of the merge fixtures is clean ten times. (4) Between v0.31.2 and main it reports only named differences of two kinds: one a fix: true story merged since v0.31.2 made, and one on the stage's allow list, which names each change the stage makes on purpose (the wider holds, the patch gate's new cases, the wrapper's lines). Each cites its merged story and states the exact lines that differ; none leaves out a whole command or file. A difference with no entry is red. A stage's run reads its own allow list and the lists of the stages before it. (5) CI reports wall time and process starts per command for two trees on a fixed fixture under stubs, and fails a command slower than its baseline by the margin the user sets. (6) The harness runs a list of commands with a python3 on PATH that fails loudly, and goes red when a listed command starts it. The allow list of stage 1 holds an entry for every output-changing story merged before the list existed, ship-gates' two at least (P14).

**Out of scope:**
- Rewriting any test: each port epic rewrites its own
- The test list and the inventory (port-inventory)
- Timing on the lead's machine or under load (rules.md:31)
- Making any command faster (HLD:90)

**Constraints:**
- stage: v0.32.0.
- Goal 2 allows two kinds of difference against v0.31.2: what a fix: true story made, each named, and the entries of the stage's allow list (HLD:60-67). The user agrees the list at the stage's exit. Each stage has its own list, in its own file, so two stages' PRs never edit the same lines.
- A fix: true story merged since v0.31.2 outside this plan is named too. dropped-lines-own-story-file is the first (HLD:76-78), and its entry is written here.
- Each stage 1 story that changes output adds its entry to stage 1's allow list in its own PR, and each folded fix its named entry.
- merge runs reconcile, its notes and ready_tell in the background (bin/lib/merge.sh:1359,1370,1429), so one global order of gh calls differs from run to run even bash against bash.
- Each new check is shown able to fail, on a copy of the worktree without .git (AGENTS.md; rules.md:25).
- The differential run runs the v0.31.2 tree, so CI keeps python3.
- CI steps use the board-only gate, add no LLM cost, and sit in their own job or workflow file.

**Your part:**
- You set the margin that counts as slower for goal 7: a kind: lead story with a You: step, which the speed fixture's story depends on. Nobody agrees the epic under the `epics` grant, so the question has its own story.
- You merge the PRs that change .github/.
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.

**Areas:**
- tests/ (harnesses, fixtures)
- scripts/ (differential run, speed fixture, allow list)
- .github/workflows/ (own job or file)

**Shared rules cited above:**
- P14: Any story, in any stage, that changes output on purpose adds its entry to its stage's allow list in its own PR, citing the story and the exact lines. port-checks writes the entries for the stories that merged before the list existed, ship-gates' two at least.

---
kind: code
status: ready
epic: board-pr-and-briefs
depends_on: []
touches: [bin/lib/lifecycle.sh:board_pr, commands/hld.md:step 5, commands/epic.md:step 5, commands/plan-epic.md:codex-review passes, commands/plan-hld.md:board PR paragraph, commands/swarm.md:board edits paragraph, bin/lib/build.sh:board_pr_merge_rule, docs/reference.md:Board PR kinds (new), docs/method.md:Who does what lead line, tests/board_pr_kinds_test.sh (new)]
estimate_lines: 220
easy: false
---

# Board PRs of kind story-scope edit, hold or finish land with no codex-review

`swarm.sh board-pr open` names the PR's kind from its name, on stderr (its stdout stays the URL that remove_item captures, bin/lib/board.sh:1514): plan-<hld> and scope-<epic> are plan PRs, agree-<slug> an HLD or epic agreement PR, finish-<slug> and drop-<slug> finish PRs, hold-<slug> a hold, any other name (a re-scope, stage-v*, check-<kind>) a story-scope edit. A plan or agreement PR's line says to run one `swarm.sh codex-review` pass before it merges; the other kinds' line says no codex-review: land it with `swarm.sh merge --board` on green CI. merge --board keeps its CI gate and runs no codex for any kind (bin/lib/merge.sh:268-310). The command text matches: commands/hld.md and epic.md step 5 open their PR as agree-<slug> and keep the pass; plan-epic.md (:37, 41, 106) and plan-hld.md (:129) keep theirs; commands/swarm.md:24-31 and board_pr_merge_rule (bin/lib/build.sh:898-906) say no codex for edits, holds and finishes (`swarm.sh hold` itself only logs, bin/swarm.sh:488-499). docs/reference.md gains a Board PR kinds list and docs/method.md's lead line (Who does what) says which board PRs skip codex. The retro-file kind is retro-report's. fixes-027's board-pr-docs-gaps and plan-hld-gaps follow this story (epic Constraints).

**Done when:**
- tests/board_pr_kinds_test.sh (new), one case per kind through its real flow with stub gh and codex: `board-pr start` and `board-pr open` under the kind's name (`swarm.sh finish <slug>` for finish) print the kind's line on stderr and the URL alone on stdout; the codex stub records no call from board-pr or merge --board; `merge --board` refuses the PR on a red head and merges it on a green one. Each case fails when its kind is named wrongly or the CI gate is skipped.
- The same test pins the codex-review pass in the four command files' plan and agreement steps, and its absence from commands/swarm.md's edit paragraph and board_pr_merge_rule's output under both merge modes.
- tests/board_pr_test.sh and tests/board_only_test.sh pass; docs/reference.md lists the kinds and tests/doc_check_test.sh passes.

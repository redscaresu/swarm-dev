---
kind: code
status: blocked
epic: ship-gates
depends_on: [lead-open-window, docs-gate-go]
needs: lead-open-window (the user's merge of the merge = human PR); docs-gate-go (it rewords AGENTS.md's release paragraph, which this story's patch sentence sits beside)
touches: [bin/lib/board.sh:non_fix_change tests-only and port: passes, bin/lib/board.sh:release_memo rule in the key, bin/lib/merge.sh:release_retro pass line, tests/next_test.sh:patch gate port and tests-only cases, tests/next_test.sh:old refusal text, tests/merge_rules_test.sh:patch refusal text, tests/merge_rules_test.sh:retro gate pass text, tests/non_fix_test.sh:rule2 cache pin and refusal text, templates/docs/stories/README.md:port field, board/stories/README.md:port field, docs/reference-merging.md:Releases fix rule (§ Releases), docs/reference-merging.md:§ The retro gate patch rule, AGENTS.md:patch rule (Rules that are not negotiable), AGENTS.md:release paragraph (Working on this repository), commands/swarm.md:release arm patch gate, commands/plan-epic.md:story fields port]
estimate_lines: 260
risk: high
---

# In swarm-dev's own repo, the patch gate passes a tests-only PR and a port: true story's PR

Uses lead-open-window's **You:** step (`merge = human` on main, so the review agent hands this PR to
the user). Builds after docs-gate-go: both reword AGENTS.md's release paragraph, on adjacent lines.

Today a patch ships only when every change since the tag is from a `fix: true` story or a fix-main
build (non_fix_change, bin/lib/board.sh:1586). The Go rewrite ships ports and test rewrites as
patches. In the plugin's own repo (the PR's repo, lower-cased, equals plugin_repo; fail closed to
today's rule when plugin_repo cannot answer), after the merged-PR, shallow-edge and fix-main checks:

- A change is a fix when its whole diff is under `tests/`. The diff is against the change's first
  parent: `git diff-tree -r --no-renames --name-only <prev> <c>`, minus board_excludes, so a story PR
  that deletes its own story file still counts.
- A `story/<slug>` change is also a fix when the story at the base has `port: true` and every
  `tests/` path of that diff equals a `tests/` file in the story's touches at the same base. Read
  `port:` with fm_text and trim it as `fix:` is trimmed (board.sh:1672). Both sides of a rename
  count. Only this repo's touches entries count. Parse touches with touches_rows.py's entries(), not
  a second parser.
- `fix: true` passes as today, and wins when both are set. `port:` gets the same base-to-merge check
  `fix:` has. A value other than `true` is refused, as `fix: x` is. The unit stays one commit: a
  rebase merge's commits are judged one by one.

In every other repo the gate is as today.

Lines to change:
- New refusal lines: `<p> had no fix: true or port: true <at>`, `<p> had port: x <at>, not true`
  and `port: true, but it changes tests/<f>, not in <p>'s touches <at>`.
- Update every quote of the old `had no fix: true` text: tests/next_test.sh:943,1047 and
  tests/merge_rules_test.sh:287, among others.
- release_retro's pass line (merge.sh:2914) says every change is from a `fix: true` story or a
  fix-main build, which turns false. It names `fix: true`, `port: true` and tests-only changes.
  Update its quotes at tests/merge_rules_test.sh:293 and docs/reference-merging.md:1181.

Rule version: one NON_FIX_RULE=2, read by non_fix_cache's file name and by release_memo's key
(board.sh:735). Then neither serves a rule-1 answer. Without it the memo serves one for up to
NON_FIX_RETRY=300 s.

Docs:
- A `port: true` list item after `fix: true` in both story READMEs, kept byte-identical
  (tests/board_readme_test.sh). The two READMEs' sentence at :18 that names `fix:` gets `port:` too.
- One new sentence per case in docs/reference-merging.md (§ Releases, § The retro gate),
  AGENTS.md:150 and the release paragraph, and commands/swarm.md's release arm. Never lengthen a
  sentence that lists them.
- commands/plan-epic.md:129 is one sentence listing story fields: give `port:` a sentence of its
  own, and add `port` beside `fix` in the schema at :78.

New cases drive swarm.sh from outside: next_test.sh's expect_release and merged_as
(next_test.sh:882-915), and merge_rules_test.sh's release fixture. non_fix_test.sh, which sources
bin/lib itself, only gets its cache pin and refusal text updated. More than two proofs, so use the
worktree copy.

**Done when:**
- In the own repo, `swarm.sh next` prints a patch release for each of: a story PR with neither
  `fix:` nor `port:` whose whole diff is under tests/, with its own story file deleted; a
  `port: true` story PR that changes bin/x and a tests/ file its touches list at the base; a
  `fix: true` story; a fix-main build
- `swarm.sh next` refuses the patch, naming the change, for each of: a `port: true` PR that changes
  one unlisted tests/ file; a `port: true` PR that adds that tests/ file to its own story's touches
  in the PR; a `port: true` story whose touches name the tests/ file only under another repo; a
  `port: true` PR whose base does not have the story (the base-to-merge check); a story with neither
  field that changes bin/x, whose line names both fields; `port: yes`
- In o/r, a tests-only story PR still refuses the patch, as today
- `merge --release` of a patch refuses a `port: true` PR with an unlisted tests/ file, and passes one
  whose tests/ files are all listed; its pass line names `fix: true`, `port: true` and tests-only
  changes
- For the same SHAs, a non-fix cache file written under rule 1 and a release memo written before the
  bump, each saying every change is a fix, are not read: next names the change that is no fix
- Each new pass and refusal goes red when its rule is broken (shown on a worktree copy, FAIL lines
  quoted); tests/board_readme_test.sh passes with the port: item in both READMEs
- scripts/select-tests.sh --run passes

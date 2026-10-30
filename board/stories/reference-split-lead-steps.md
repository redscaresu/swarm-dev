---
kind: lead
status: ready
epic: reference-split
after: reference-split
depends_on: []
touches: []
estimate_lines: 0
easy: false
---

# Lead: set the three 0.28 epics active only after the split, so they plan on the new files

after: reference-split. The epic's Your part (board/epics/reference-split.md:32-34). **You:** when `next` prints `stage v0.31.0`, follow release-v0-30-0 step 5 (board/stories/release-v0-30-0.md:18). The stage PR sets flaky-tests, board-loose-ends, machine-usable, merge-mechanics and deferred-700 active. A second board PR sets retro-gate, retro-report and handover-usage active, but only once every PR of this epic has merged, so their stories' touches name the docs/reference-<group>.md files. Until then, next's `stage v0.31.0` line for those three is expected: do not act on it. **You:** if any PR of this epic changed hooks/merge-guard.sh (the plan keeps it unchanged), merge that PR by hand as a protected-path change. **You:** decide the Goal 10 reading: flow merge_ins' file-conflicts block prints only its top three files, per file (bin/lib/flow_merge_ins.py:151-152), so once split the docs/reference*.md bar can read wrong. Either file a follow-up story or issue for a deduplicated docs/reference*.md count in flow, or accept the row as it is and say so in the release-v0-30-0 PR.

**Done when:**
- The board PR that sets retro-gate, retro-report and handover-usage active merged on main after the last PR of this epic (git log --first-parent order).
- No story file added for those three epics after the split names docs/reference.md in its touches, except for § Commands rows the entry file kept.
- `git log --name-only` over this epic's PRs lists no file under hooks/, or the PR that does was merged by hand.
- The Goal 10 reading is decided: a follow-up for the flow count exists, or the release-v0-30-0 PR body says the row is accepted as it is.

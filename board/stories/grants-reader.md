---
kind: code
status: ready
epic: hld-grants
depends_on: []
touches: [bin/lib/board.sh:new hld_grants and item_hld, bin/swarm.sh:grants dispatch arm, commands/plan-epic.md:approval steps, commands/swarm.md:never-merge lines, templates/docs/hld/README.md, board/hld/README.md, tests/grants_test.sh (new)]
estimate_lines: 200
easy: false
---

# swarm.sh grants names the HLD over a story, epic or PR and what it grants, and /plan-epic skips its approval under `stories`

- **The readers (bin/lib/board.sh).** `hld_grants <hld file>` reads `grants:` from the front matter only (get_fm, bin/lib/board.sh:663; never `fm`, which can match a body line) as a list (slug_list). An absent line means none. A value other than `epics`, `stories`, `merge` or `release` dies with `<path>:<line>: grants must be epics, stories, merge or release`, the way the config parser does (bin/swarm.sh:204-205, 239). `item_hld <story or epic file>` walks story → `epic:` → `parent:` … to the first epic with `hld:`, keeping a seen list so a `parent:` cycle ends (the walk at bin/lib/board.sh:475). It prints the HLD file only when the HLD's status is `agreed`. It fails closed, printing nothing, on a missing epic, a missing HLD file, or a draft or superseded HLD.
- **The command.** `swarm.sh grants <story | epic | PR URL>` prints the HLD file and its grants, one per line, or `none`. A PR URL resolves a story PR through pr_stories (its `prs:` line) and a board PR through the `epics/*.md` and `stories/*.md` its diff touches, including a deleted file at the base. When those fall under two HLDs, or any of them under none, it prints `none`. hld-grants' later stories and the sibling epics plan-hld and epic-guard use these readers; do not name plan-hld in code or comments (tests/removed_test.sh still forbids it).
- **The prompts.** commands/plan-epic.md runs `swarm.sh grants <epic>` before its approval points, "Ask before writing anything" on the full path and "asks before board-pr open" on the small path and the split. With `stories` listed, it writes the stories and opens the board PR without asking, and says so in its report. commands/swarm.md's never-merge lines (:29, :139, :244) say that under `merge = human` the lead merges only a PR `swarm.sh grants <PR>` lists `merge` for, or a release PR it lists `release` for.
- **The template.** templates/docs/hld/README.md and board/hld/README.md define the four grants in one line each, and say an absent `grants:` means none and only the user sets it. The two files stay byte-equal (tests/board_readme_test.sh).

**Done when:**
- tests/grants_test.sh, on a fixture board: a story under a child epic whose parent has `hld:` resolves to that HLD's grants; a draft HLD, a superseded one, a missing HLD file and a story with no epic each print `none`; a `parent:` cycle ends; a bad grant value dies with the file and line; a stub-gh board PR touching epics under two HLDs prints `none`.
- doc_check passes with the new `swarm.sh grants` in commands/*.md.
- `make test` passes.

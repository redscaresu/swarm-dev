---
kind: docs
status: ready
epic: doc-hotspot
depends_on: []
touches: [docs/reference-lead.md:Commands (every row, as blocks)]
estimate_lines: 90
easy: true
---

# Turn docs/reference-lead.md's Commands table into one block per command

No depends_on: no open story or PR edits these rows. Before the split, the `wait --lead` row (now docs/reference-lead.md:716, 433 words) was the hottest docs line: 27 of the 88 conflicted merge-ins with a docs/reference.md conflict (2026-10-25 to the split). Replace the table (:713-720) with blocks. The lines `wait --lead` waits for become a list, one line kind per item, sorted; the same for `restart` (:717, 341 words) and `hold`. board-loose-ends' lead-wait-planned-line and lead-wait-plan-missing-line add `wait --lead` lines without naming this row: if one is in review when this starts, expect one conflict. Block format, the same in every reference file: keep the `## Commands` heading (links to `#commands` hold); one block per table row, sorted by command, a blank line between blocks; the block's first line is the row's first cell in bold (**`swarm.sh status`**), then the row's text, one sentence per line. Layout only: every statement stays, word for word. In the text it changes, one sentence per line, and a list that features add to (events, fields, lines, sections, options) becomes a list, one item per line, sorted by its key, so a new item lands at its own place and two stories adding items edit different lines (git conflicts by line). Word check for the PR body: `tr -cs '[:alnum:]_' '\n' < <file> | sort` at the PR's base and at its head differ only in words the body lists (a dropped `and`, a repeated lead-in).

**Done when:**
- docs/reference-lead.md § Commands has no table row: one block per command, sorted, and the wait --lead block lists its line kinds one per item, sorted.
- `awk '/^## Commands/{c=1} /^## /&&!/^## Commands/{c=0} c && NF>150 {print FNR": "NF}' docs/reference-lead.md` prints nothing.
- The word check on docs/reference-lead.md differs only in words the PR body lists.
- scripts/select-tests.sh --run passes (it selects the docs tests: doc_check, epic_codex, skill, command_names and the rest).

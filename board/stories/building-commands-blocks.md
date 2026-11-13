---
kind: docs
status: blocked
epic: doc-hotspot
depends_on: [next-follows-moved-head]
needs: [next-follows-moved-head (its review-agent --next row edit (#814) merged first; so this story moves the final text)]
touches: [docs/reference-building.md:Commands (every row, as blocks), docs/reference-building.md:review-agent rows (Commands)]
estimate_lines: 130
easy: false
---

# Turn docs/reference-building.md's Commands table into one block per command

Needs next-follows-moved-head merged: its PR (#814) edits the review-agent --next row (reference-building.md:1105 on its base). The table (docs/reference-building.md:1102-1113) has ten rows, seven of them over 150 words (review-agent --recheck: 409). Before the split, the review-agent row was in 8 of the 88 docs conflicts, story 2, status 1. Replace the table with blocks. Line 72 (193 words, § Building) belongs to doc-line-cap. Block format, the same in every reference file: keep the `## Commands` heading (links to `#commands` hold); one block per table row, sorted by command, a blank line between blocks; the block's first line is the row's first cell in bold (**`swarm.sh status`**), then the row's text, one sentence per line. Layout only: every statement stays, word for word. In the text it changes, one sentence per line, and a list that features add to (events, fields, lines, sections, options) becomes a list, one item per line, sorted by its key, so a new item lands at its own place and two stories adding items edit different lines (git conflicts by line). Word check for the PR body: `tr -cs '[:alnum:]_' '\n' < <file> | sort` at the PR's base and at its head differ only in words the body lists (a dropped `and`, a repeated lead-in).

**Done when:**
- docs/reference-building.md § Commands has no table row: one block per command, sorted.
- `awk '/^## Commands/{c=1} c && NF>150 {print FNR": "NF}' docs/reference-building.md` prints nothing.
- The word check on docs/reference-building.md differs only in words the PR body lists.
- scripts/select-tests.sh --run passes (it selects the docs tests: doc_check, epic_codex, skill, command_names and the rest).

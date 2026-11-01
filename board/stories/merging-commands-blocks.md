---
kind: docs
status: blocked
epic: doc-hotspot
depends_on: [release-upgrade-confirm, wait-pr-poll-cache, next-follows-moved-head]
needs: [release-upgrade-confirm (its edits to this table (#825) merged first), wait-pr-poll-cache (its wait-pr row text merged first), next-follows-moved-head (its review row edit (#814) merged first)]
touches: [docs/reference-merging.md:Commands (every row, as blocks), docs/reference-merging.md:wait-pr row (Commands)]
estimate_lines: 120
easy: false
---

# Turn docs/reference-merging.md's Commands table into one block per command

Needs three stories merged first. release-upgrade-confirm: its PR (#825) edits this table (reference-merging.md:930-970 on its base) and names § Commands. wait-pr-poll-cache: it rewrites the wait-pr row. next-follows-moved-head: its PR (#814) edits the review row (:949 on its base), though its touches name only reference-building.md. The table (docs/reference-merging.md:957-964) has six rows, five over 150 words (wait-pr: 711). Before the split, merge was in 3 of the 88 docs conflicts, init 3, wait-pr 1. Replace the table with blocks. Line 83 (514 words, § Merging) belongs to doc-line-cap. Block format, the same in every reference file: keep the `## Commands` heading (links to `#commands` hold); one block per table row, sorted by command, a blank line between blocks; the block's first line is the row's first cell in bold (**`swarm.sh status`**), then the row's text, one sentence per line. Layout only: every statement stays, word for word. In the text it changes, one sentence per line, and a list that features add to (events, fields, lines, sections, options) becomes a list, one item per line, sorted by its key, so a new item lands at its own place and two stories adding items edit different lines (git conflicts by line). Word check for the PR body: `tr -cs '[:alnum:]_' '\n' < <file> | sort` at the PR's base and at its head differ only in words the body lists (a dropped `and`, a repeated lead-in).

**Done when:**
- docs/reference-merging.md § Commands has no table row: one block per command, sorted.
- `awk '/^## Commands/{c=1} c && NF>150 {print FNR": "NF}' docs/reference-merging.md` prints nothing.
- The word check on docs/reference-merging.md differs only in words the PR body lists.
- scripts/select-tests.sh --run passes (it selects the docs tests: doc_check, epic_codex, skill, command_names and the rest).

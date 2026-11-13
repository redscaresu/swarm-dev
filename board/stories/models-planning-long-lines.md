---
kind: docs
status: blocked
epic: doc-hotspot
depends_on: [stall-live-test-run, pane-close-event]
needs: [stall-live-test-run (its stall_minutes edit (#815) merged first), pane-close-event (its stall_minutes edit (#826) merged first)]
touches: [docs/reference-models.md:stall_minutes item (§ Settings), docs/reference-models.md:queue_minutes item (§ Settings), docs/reference-models.md:escalate_ladder item (§ Settings), docs/reference-models.md:lead item (§ Settings), docs/reference-models.md:merge_admin item (§ Settings), docs/reference-models.md:review_verify item (§ Settings), docs/reference-models.md:TEST_FILE_TIMEOUT item (§ Settings), docs/reference-models.md:Commands (the row, as a block), docs/reference-planning.md:Commands (the /epic and grants rows, as blocks)]
estimate_lines: 140
easy: false
---

# One sentence per line in reference-models.md's long Settings items, and blocks for the models and planning Commands

Needs stall-live-test-run and pane-close-event merged: both PRs (#815, #826) edit the `stall_minutes` item (reference-models.md:125-131 on their bases), one 798-word line, and conflict with each other on it today; #826's touches do not name this file. § Settings (docs/reference-models.md:126-145) already has one list item per setting, but seven items are single lines over 150 words: stall_minutes (:128, 798), queue_minutes (:129), escalate_ladder (:132), lead (:139), merge_admin (:140), review_verify (:141), TEST_FILE_TIMEOUT (:145). Before the split § Settings was in 6 of the 88 docs conflicts. Rewrap each of those items one sentence per line, continuation lines indented two spaces so they stay in the item; a list inside an item becomes a nested list, sorted. Turn the one-row Commands tables of docs/reference-models.md and docs/reference-planning.md (:203, 414 words) into blocks. Block format, the same in every reference file: keep the `## Commands` heading (links to `#commands` hold); one block per table row, sorted by command, a blank line between blocks; the block's first line is the row's first cell in bold (**`swarm.sh status`**), then the row's text, one sentence per line. Layout only: every statement stays, word for word. In the text it changes, one sentence per line, and a list that features add to (events, fields, lines, sections, options) becomes a list, one item per line, sorted by its key, so a new item lands at its own place and two stories adding items edit different lines (git conflicts by line). Word check for the PR body: `tr -cs '[:alnum:]_' '\n' < <file> | sort` at the PR's base and at its head differ only in words the body lists (a dropped `and`, a repeated lead-in). Correction: reference-planning.md's Commands table has two rows, /epic and grants (:202-203), not one.

**Done when:**
- `awk 'NF>150 {print FILENAME":"FNR": "NF}' docs/reference-models.md docs/reference-planning.md` prints nothing.
- Each § Settings item is still one list item per setting; neither file has a Commands table row.
- The word check on docs/reference-models.md and on docs/reference-planning.md differs only in words the PR body lists.
- scripts/select-tests.sh --run passes (it selects the docs tests: doc_check, epic_codex, skill, command_names and the rest).
- reference-planning.md's Commands has a block for /epic and one for grants.

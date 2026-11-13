---
kind: docs
status: blocked
epic: doc-hotspot
depends_on: [model-fit-by-effort, flow-panes, flow-test-runs-timeouts, run-times-by-load]
needs: [model-fit-by-effort (its flow-row and model_fit edits (#816) merged first; so this story moves the row's final text), flow-panes (its edit of the flow row's section list (reference-logs.md Commands); which this rewrites as a block), flow-test-runs-timeouts (its edit of the same flow row), run-times-by-load (its edit of the same flow row)]
touches: [docs/reference-logs.md:Commands (every row, as blocks)]
estimate_lines: 150
easy: false
---

# Turn docs/reference-logs.md's Commands table into one block per command

Needs model-fit-by-effort merged: its PR (#816) edits the flow row (reference-logs.md:916 on its base). Each Commands row is one physical line. The flow row (docs/reference-logs.md:923) is 1,080 words and every flow story edits it: 11 of the 47 docs conflicts since the split; log-finding's row (:919, 155 words) 4 more. Replace the table (:915-923) with blocks. flow's sections become a list, one section per item, sorted by section name; log-finding's options a list. tests/epic_codex_test.sh:28 counts lines that name `log-finding` without `--reviewer`: keep `--reviewer` on each such line. docs/reference.md:17 still says 'table'; doc-line-cap changes it once all six files are blocks. Block format, the same in every reference file: keep the `## Commands` heading (links to `#commands` hold); one block per table row, sorted by command, a blank line between blocks; the block's first line is the row's first cell in bold (**`swarm.sh status`**), then the row's text, one sentence per line. Layout only: every statement stays, word for word. In the text it changes, one sentence per line, and a list that features add to (events, fields, lines, sections, options) becomes a list, one item per line, sorted by its key, so a new item lands at its own place and two stories adding items edit different lines (git conflicts by line). Word check for the PR body: `tr -cs '[:alnum:]_' '\n' < <file> | sort` at the PR's base and at its head differ only in words the body lists (a dropped `and`, a repeated lead-in).

**Done when:**
- docs/reference-logs.md § Commands has no table row: one block per command, sorted, and the flow block lists its sections one per item, sorted.
- `awk '/^## Commands/{c=1} /^## /&&!/^## Commands/{c=0} c && NF>150 {print FNR": "NF}' docs/reference-logs.md` prints nothing.
- The word check on docs/reference-logs.md differs only in words the PR body lists.
- scripts/select-tests.sh --run passes (it selects the docs tests: doc_check, epic_codex, skill, command_names and the rest).
- No table-only `\|` escape is left; each command synopsis renders as before.

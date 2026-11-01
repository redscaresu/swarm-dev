---
kind: docs
status: blocked
epic: doc-hotspot
depends_on: [pane-close-event]
needs: [pane-close-event (its pane-closed line and fields in § Logs and outcomes (#826); merged first so this list includes them and the two PRs do not conflict)]
touches: [docs/reference-logs.md:Logs and outcomes (outcome-field tail paragraph: the callers sentence)]
estimate_lines: 30
easy: true
---

# List the event tail's callers one per line in docs/reference-logs.md

Needs pane-close-event merged: its PR (#826) edits this paragraph (reference-logs.md:174 on its base) to add the pane-closed line's fields, and this story lists them with the rest. The sentence 'Callers can pass fields of their own, which come before `version=`: ...' (docs/reference-logs.md:162-166) is the hottest docs line found: 27 of the 47 conflicted merge-ins with a docs/reference*.md conflict since the split hit it, each story adding its caller's clause. Turn it into a lead-in line and a list, one caller per item (`merge` passes `hold=` on its held lines, `intervene` passes `cause=`, ...), sorted by command. Leave the rest of the outcome-field tail paragraph (:157-180) as it is. Layout only: every statement stays, word for word. In the text it changes, one sentence per line, and a list that features add to (events, fields, lines, sections, options) becomes a list, one item per line, sorted by its key, so a new item lands at its own place and two stories adding items edit different lines (git conflicts by line). Word check for the PR body: `tr -cs '[:alnum:]_' '\n' < <file> | sort` at the PR's base and at its head differ only in words the body lists (a dropped `and`, a repeated lead-in).

**Done when:**
- docs/reference-logs.md's outcome-field tail paragraph gives the callers' fields one caller per list item, sorted by command; no caller's fields are left in a running sentence.
- The word check on docs/reference-logs.md differs only in words the PR body lists.
- In a scratch clone, two branches off the PR's head that each add an item for a different caller, at places that are not next to each other, merge clean (`git merge-tree --write-tree` exits 0); the same two additions made as clauses on the PR's base conflict (exit 1). The PR body quotes both exit codes.
- scripts/select-tests.sh --run passes (it selects the docs tests: doc_check, epic_codex, skill, command_names and the rest).

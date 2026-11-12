---
kind: docs
status: blocked
epic: doc-hotspot
depends_on: [logs-event-tail-list, review-pane-closes-after-merge, review-pane-closes-after-handover]
needs: [logs-event-tail-list (the tail paragraph already a list; the same § Logs and outcomes part; so this goes second (and after pane-close-event; which that story waits on and which also edits the audit log; #826 at :81)), review-pane-closes-after-merge (its audit-log edit (#819) merged first; so it moves into an entry instead of conflicting), review-pane-closes-after-handover (its line in the audit log paragraph (reference-logs.md:130))]
touches: [docs/reference-logs.md:Logs and outcomes (the audit log paragraph)]
estimate_lines: 300
easy: false
---

# Split the audit log paragraph into one entry per command

Needs logs-event-tail-list merged (same part, § Logs and outcomes), and review-pane-closes-after-merge merged: its PR (#819) edits this paragraph (reference-logs.md:130 on its base) though its touches do not name the file. **The audit log.** (docs/reference-logs.md:7-155) is one 150-line paragraph that names every command's event lines. In the replay, 6 of the 47 docs conflicts fell inside it, and in a sentence-per-line re-merge 12 more were two stories appending at its end (after 'The outcome field is the one place free text gets in', :153). Keep the general rule (:7-14: what every line holds, the read-only exemption) as the lead-in, then one list item or short paragraph per command or event kind (`close`, `merge`, `review`, `review-agent`, `tell`, `wait`, `wait --stall`, `wait-pr`, `watch`, the incident lines, ...), sorted by command, each holding its existing sentences. Keep the bold lead-in **The audit log.** and every cross-reference ('(below)', '§ Building'). Layout only: every statement stays, word for word. In the text it changes, one sentence per line, and a list that features add to (events, fields, lines, sections, options) becomes a list, one item per line, sorted by its key, so a new item lands at its own place and two stories adding items edit different lines (git conflicts by line). Word check for the PR body: `tr -cs '[:alnum:]_' '\n' < <file> | sort` at the PR's base and at its head differ only in words the body lists (a dropped `and`, a repeated lead-in).

**Done when:**
- The audit log in docs/reference-logs.md is the lead-in plus one entry per command or event kind, sorted by command; no entry holds another command's event lines.
- The word check on docs/reference-logs.md differs only in words the PR body lists.
- scripts/select-tests.sh --run passes (it selects the docs tests: doc_check, epic_codex, skill, command_names and the rest).

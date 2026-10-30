---
kind: docs
status: blocked
epic: reference-split
depends_on: [reference-split-move, reference-conflict-reading]
needs: [reference-split-move (the group files and the entry's ## Commands table), reference-conflict-reading (the § Commands conflict count the PR quotes)]
touches: [docs/reference.md:Commands, docs/reference-lead.md:Commands (new), docs/reference-planning.md:Commands (new), docs/reference-models.md:Commands (new), docs/reference-building.md:Commands (new), docs/reference-logs.md:Commands (new), docs/reference-merging.md:Commands (new), README.md:Watching it commands sentence]
estimate_lines: 90
easy: true
---

# Move each ## Commands row of docs/reference.md next to the section that documents its command

Needs: from reference-split-move, the group files and the entry's ## Commands table. From reference-conflict-reading, its § Commands count, which the PR quotes as the reason for the move. The table (docs/reference.md:3746-3782 today, 33 rows) was the section most often edited: 32 of the 78 reference.md commits in v0.28.0..v0.29.0 (survey scan). A story that changes a command edits its section and its row, so while the table is shared, any two such stories clash on docs/reference.md:Commands. Move each row verbatim into a ## Commands table at the end of the group file whose section documents its command. A row no section documents goes to the group file nearest its topic, so no command row stays in the entry. The entry's ## Commands becomes links to each group file's table, so README.md:130's docs/reference.md#commands still resolves. Reword README.md:130's 'lists them all' to say where the commands are. Run humanizer on that sentence, the entry's new lines and the PR body. The PR body lists each row's command and its file.

**Done when:**
- The PR body quotes reference-conflict-reading's § Commands count.
- Every row of the base's ## Commands table appears exactly once across docs/reference*.md on the head, unchanged; the PR body shows the check and its output.
- The PR body's mapping names each row's file and the section that documents it, and for a row no section documents, why that file.
- The anchor check passes, README.md:130 no longer says the entry file lists every command, and scripts/select-tests.sh --run passes.
- The entry file's ## Commands holds no command row, only links to the group files' tables.

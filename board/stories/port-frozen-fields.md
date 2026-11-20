---
kind: code
status: ready
epic: port-inventory
depends_on: []
touches: [docs/port/fields.tsv, tests/port_fields_test.sh]
estimate_lines: 200
---

# docs/port/fields.tsv freezes the board front-matter fields the code reads, with their readers, and a test fails when no reader names one

Needs no other story.
- Write docs/port/fields.tsv (`#` header: file kind, field, read_by), drawn at the story's base: v0.31.3's fields plus any added since (patch-gate-port's `port`); the header says so. One row per front-matter field the code reads from a story, epic, HLD or retro file, through fm, get_fm, fm_list, fm_text and the Python readers. The code has no list of them: SET_FM_KEYS has only the fields swarm.sh writes. read_by: the file:function entries whose body reads it.
- Add tests/port_fields_test.sh. For each row, at least one read_by entry must still be a function in that file (a bash `name() {`, a Python `def name(`, or a Go `func Name(` or method) whose body names the field as a whole word. Scan bin/, hooks/, cmd/ and internal/ (skip *_test.go). A port that moves a reader points read_by at the new function, where the reviewer sees it. It fails naming the field and its readers, and each failure line names docs/port/fields.tsv. Source tests/test_helpers.sh first. List files with find (skip __pycache__, *.pyc), not git, so the test runs the same on a copy of the worktree without .git.
- The test reads the code, not the template READMEs: a doc would stand in for the reader (rules.md:9). Edit no README.
- Prove it red on a copy without .git: a field's name removed from the body of its only reader, and a reader function renamed. Show green when a Go reader in internal/x/x.go that names the field replaces the bash one in read_by.
- The PR gives the count with its population: fields per file kind.
- Humanizer over the header lines and the PR body.

**Done when:**
- fields.tsv names every field the code reads at the base, each with a reader. tests/port_fields_test.sh passes, goes red on both seeded cases on a copy without .git, and stays green when read_by points at a Go reader.
- scripts/select-tests.sh --run passes

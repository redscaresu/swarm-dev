---
kind: code
status: ready
epic: port-inventory
depends_on: []
touches: [docs/port/swarm-names.tsv, tests/port_swarm_names_test.sh]
estimate_lines: 210
---

# docs/port/swarm-names.tsv lists every SWARM_* name the code reads, and a test fails on a name it lacks or a listed name that is gone

Needs no other story.
- Write docs/port/swarm-names.tsv (`#` header: name, kind, files). One row per distinct SWARM_[A-Z0-9_]+ name in the files under bin/ and hooks/, and under cmd/ and internal/ once go-module adds them (skip *_test.go). kind: setting (a user or CI sets it), handoff (one swarm-dev process passes it to another) or seam (only tests set it). files: the files that name it, no lines.
- Add tests/port_swarm_names_test.sh. It fails on a name found with no row, naming the name and file. It also fails on a row whose name no scanned file has, so a port that drops a name deletes its row where the reviewer sees it. Each failure line names docs/port/swarm-names.tsv and the row to add or delete. Source tests/test_helpers.sh first. List files with find (skip __pycache__, *.pyc), not git, so the test runs the same on a copy of the worktree without .git. A plain grep over bin/ counts 130 because of untracked __pycache__ files; the tracked count is 126 (survey).
- Match the token in any file type, Go included, with no Go-specific parse, so the test stays live after the bash goes (bash-retired). go-module-build's cmd/swarm/main.go reads no SWARM_ name (.swarm/go-module/lead.json, go-module-build scope), so it needs no row.
- Prove it red on a copy without .git: a new name in a bin/lib file, one in a hooks file, one in internal/x/x.go, and a name's only mention removed.
- The PR gives the count with its population: names over N files under bin/ and hooks/, and how many only .py files read.
- Humanizer over the header lines and the PR body.

**Done when:**
- swarm-names.tsv has one row per name found at the base, each with a kind. tests/port_swarm_names_test.sh passes and goes red on each of the four seeded cases on a copy without .git.
- scripts/select-tests.sh --run passes

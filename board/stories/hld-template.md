---
kind: code
status: ready
epic: hld-command
depends_on: []
touches: [templates/docs/hld/README.md (new), board/hld/README.md, templates/docs/Board.base, board/Board.base, tests/init_test.sh, tests/removed_test.sh, tests/board_readme_test.sh]
estimate_lines: 90
easy: true
---

# swarm.sh init writes the HLD template and an HLD view on the board

The template is the old one, at `git show 47a8ced9^:templates/docs/hld/README.md` (33 lines; board/hld/README.md is a copy of it). Its front matter is `title`, `date`, `status: draft | agreed | superseded` and a new `grants: []` line. Its body has the ten sections Problem, Goals, Non-goals, Current state, Design, Alternatives, Risks and safety, Rollout, Open questions and Epics. Its note says an epic links back with `hld: <file-name-without-.md>`, and that `superseded` is set by hand, by the user. init copies every file under templates/docs (bin/swarm.sh:1472, 1493), so adding the file is enough for init to write it. board/hld/README.md is updated to match, and tests/board_readme_test.sh's byte-compare loop gains `hld`.

templates/docs/Board.base and board/Board.base each get an HLD view: `file.inFolder("hld")`, with status and date columns, grouped by status. The old HLDs.base at 47a8ced9^ shows the shape.

tests/removed_test.sh:36-42 asserts that templates/docs/hld does not exist. Drop that one assertion and keep the `plan-hld`, `hld-lead` and commands/plan-hld.md checks; the plan-hld epic removes those.

**Done when:**
- tests/init_test.sh checks that an init'd board has `<board>/hld/README.md` with a `grants: []` line and the ten section headings, and that its Board.base has a view filtering `inFolder("hld")`.
- tests/board_readme_test.sh compares board/hld/README.md with templates/docs/hld/README.md.
- `make test` passes.

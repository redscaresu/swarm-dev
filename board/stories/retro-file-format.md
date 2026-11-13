---
kind: code
status: ready
epic: retro-report
depends_on: []
touches: [templates/docs/retros/README.md, board/retros/README.md, templates/docs/Board.base:properties and views, board/Board.base:properties and views, tests/board_readme_test.sh:README loop, tests/init_test.sh:fresh board's files, docs/reference-lead.md:Retro files paragraph (new)]
estimate_lines: 110
easy: false
---

# The retro file format on the board: README pair, covers:/done: fields, a Retros view

Add templates/docs/retros/README.md and an identical board/retros/README.md. They say that a retro file is retros/v<version>.md with front matter `covers: v<from>..v<to>` and `done: YYYY-MM-DD`. Each goes on one line with no quotes, because retro-gate's check reads them in bash 3.2. The body records each item of the retro report's lists and what became of it: a story, a check, a rule (rules.md, a project's brief or AGENTS.md), or a drop with its reason. It also records which swarm.sh wrote the report. The retro is a kind: lead story `retro-<version with dots as ->`, such as retro-v0-31-0, with **You:** steps. Its file lands by board PR. A rule it places lands in its own PR first. A file in retros/ that lacks either field is a note, and no check reads it as a retro. That covers board/retros/v0.28.0.md, v0.30.0.md and the planned v0.31.0-checkpoint.md, which stay as they are. Add `covers` and `done` properties to templates/docs/Board.base and board/Board.base (identical today), and a Retros view that filters on a covers value being set, not on file.inFolder. That way README.md and the notes stay out of it. Extend tests/board_readme_test.sh's loop (:24) to retros. Add an awk check like the stage: one (:35) that the README's front-matter block shows covers: and done:. Add a **Retro files.** paragraph to docs/reference-lead.md that points at the README. These docs never name `swarm.sh retro`: the README speaks of the retro report's lists. That keeps doc_check green whichever story merges first. Avoid removed_test.sh's banned phrases, such as 'release story'. One sentence per line in docs (the coming 150-word line cap, board/stories/doc-line-cap.md).

**Done when:**
- tests/board_readme_test.sh compares board/retros/README.md with templates/docs/retros/README.md. It fails when the README's front-matter block drops covers: or done:.
- tests/init_test.sh asserts that a freshly initialised board holds retros/README.md and that its Board.base has the Retros view with the covers filter, and passes.
- tests/doc_check_test.sh passes. The new checks fail on a worktree copy with the covers: line removed, and the PR body has the FAIL lines. The PR says the humanizer ran over the README and docs prose.

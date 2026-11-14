---
kind: docs
status: ready
epic: retro-gate
depends_on: []
touches: [templates/docs/stories/README.md:fix paragraph (new), board/stories/README.md:fix paragraph (new), commands/plan-epic.md:lead.json schema (:60) and front-matter list (:105)]
estimate_lines: 20
easy: true
---

# The stories README and /plan-epic name fix: true, for a story that fixes shipped behaviour

A story field that says the story fixes behaviour a release already shipped. non-fix-change, next-retro-step and release-retro-gate read it. This PR documents it so planners start setting it. Edit templates/docs/stories/README.md and board/stories/README.md identically (tests/board_readme_test.sh compares them): add a paragraph after the kind paragraph. `fix: true` marks a story that fixes shipped behaviour (a bug, a regression). A patch release is meant to carry only such stories and fix-main builds. New behaviour never carries it. In commands/plan-epic.md, add fix to the scoping schema (:60) and to the front-matter list the lead writes (:105), set only on a story that fixes shipped behaviour. State only what holds before the gate lands: no line says a release check reads the field yet. One sentence per line; humanizer over the prose.

**Done when:**
- Both READMEs carry the fix: paragraph and tests/board_readme_test.sh passes. On a worktree copy with the paragraph in only one README, it fails; the PR body has the FAIL line.
- commands/plan-epic.md's schema line (:60) and front-matter list (:105) name fix. tests/doc_check_test.sh passes, and the PR says the humanizer ran.

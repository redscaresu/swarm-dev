---
kind: docs
status: ready
epic: stage-gating
depends_on: []
touches: [board/epics/README.md:front matter, templates/docs/epics/README.md:front matter, docs/reference.md:Writing an epic, tests/board_readme_test.sh:epics stage check]
estimate_lines: 30
easy: true
---

# The epics README documents stage: and who sets a staged draft active

Add `stage: v<x.y.0>` with a short comment to the front-matter block of board/epics/README.md (:15-38) and, byte for byte, templates/docs/epics/README.md (tests/board_readme_test.sh:24-33 compares them). Add prose: an epic in a staged HLD's Rollout carries its stage; a draft epic with stage: and hld: is set active by the lead, under its HLD's `epics` grant, once the stage before it is tagged, not through /epic; a stage's release waits until every epic of that stage has left the board. Name stage: in docs/reference.md § Writing an epic (:137-170) with a link to § Releases. Add a check to tests/board_readme_test.sh that fails when board/epics/README.md's front-matter block has no `stage:` line. Markdown links only, no wikilinks. Add no front-matter schema check that rejects boards without stage: (epic Constraints).

**Done when:**
- Both epics READMEs carry the stage: line and the prose and still match; tests/board_readme_test.sh passes, and fails when the stage: line is removed from both copies.
- docs/reference.md § Writing an epic names stage:; doc_check passes.

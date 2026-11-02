---
kind: docs
status: ready
epic: board-loose-ends
depends_on: []
touches: [docs/lead-by-hand.md:#696 entry]
estimate_lines: 15
easy: true
---

# docs/lead-by-hand.md: remove the #696 entry

docs/lead-by-hand.md still has the #696 entry, `## A builder that loads the machine or reads session logs`. On main it is at lines 40-51, not 91-96 as the epic says; cite it by heading. #696 is closed. The file holds steps with an open issue (docs/lead-by-hand.md:3-4), and rules.md:31 and :33 carry the two rules. The v0.30.0 release docs PR (#805) kept and reworded the entry because builders still started broad local runs. machine-usable's push-once change (HLD v0.31.0 additions, retro decision 1) is that symptom's fix. Delete the entry, from its heading through its Issue line, and nothing else. git grep finds no other link to it. Say in the PR body that humanizer ran over the PR description; the change only deletes prose.

**Done when:**
- On the PR head, docs/lead-by-hand.md has no `A builder that loads the machine or reads session logs` heading and no link to issues/696. `git diff origin/main` shows only that entry's lines removed.
- CI's test job on the PR head passes, including tests/doc_check_test.sh and tests/board_readme_test.sh.

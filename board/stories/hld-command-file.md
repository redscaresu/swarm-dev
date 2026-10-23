---
kind: code
status: blocked
epic: hld-command
depends_on: [hld-template]
needs: templates/docs/hld/README.md, the template /hld copies
touches: [commands/hld.md (new), bin/swarm.sh:ROLE_GROUPS and policy, tests/command_names_test.sh, tests/roles_test.sh, docs/features.tsv]
estimate_lines: 160
easy: false
---

# /hld writes an HLD with the user and sets it agreed only on the user's word

Needs hld-template's templates/docs/hld/README.md, which /hld copies.

commands/hld.md mirrors commands/epic.md (steps 0 to 5), with these differences:
- The file is `<board>/hld/YYYY-MM-DD-<slug>.md`, made from the template with `title:` and `date:` filled in. `D` is `.swarm/hld-<slug>`.
- With no title, it resumes the HLD in progress by grepping `^status: draft$` in `<board>/hld/*.md` (never the README). With several, it asks which.
- Agents start in the tab `_hld`: the co-author is `swarm.sh agent _hld hld-<slug> "$PWD" hld <brief>`, and the reviewer is `swarm.sh agent _hld hld-review-<slug> "$PWD" hld-review <brief>`. Close them by name, never `swarm.sh close hld`.
- The co-author brief asks the user about `grants:` (epics, stories, merge, release) and never fills it in by itself. The reviewer brief attacks the draft's `grants:` as a risk, along with what epic.md's reviewer attacks.
- Step 5 sets `status: agreed` (not active) once `D/agreed` exists, opens the board PR with one codex-review pass, and closes both agents by name. It must not name `plan-hld`, since tests/removed_test.sh still forbids it; the plan-hld epic adds the line pointing at it.
- Front matter `description:` starts "Use when asked to write, start or resume an HLD or a design", with an `argument-hint:`, like epic.md.

bin/swarm.sh: ROLE_GROUPS' design group gains `hld,hld-review,hld-lead`, and policy() gets `hld) claude fable high`, `hld-review) claude fable xhigh` and `hld-lead) claude fable xhigh` (the old values, at 47a8ced9).

Tests: tests/command_names_test.sh:5 and 21-24 now require commands/hld.md to exist. tests/roles_test.sh:57-61 now require the three roles to exist and `swarm.sh policy` to answer for each. Its reached-by-a-literal-caller check covers `hld` and `hld-review` through commands/hld.md. `hld-lead` has no caller until plan-hld; exempt it in the test with a comment naming the plan-hld epic. docs/features.tsv gets the hld and hld-review rows if features_test asks for them.

**Done when:**
- `swarm.sh policy hld`, `policy hld-review` and `policy hld-lead` print their policies, and tests/roles_test.sh checks this.
- tests/command_names_test.sh passes with commands/hld.md present, and `claude plugin validate .` passes in CI.
- commands/hld.md sets `status: agreed` only after `D/agreed` exists, and plan_epic_test-style phrase checks in a test assert the close-by-name lines and the `_hld` tab.
- `make test` passes.

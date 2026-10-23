---
kind: docs
status: ready
epic: epic-guard
depends_on: []
touches: [commands/epic.md:step 3 and step 5, commands/swarm.md:gate draft-epic text, skills/swarm-dev/SKILL.md:Why stopped, templates/docs/epics/README.md:front matter block, board/epics/README.md:front matter block, tests/plan_epic_test.sh]
estimate_lines: 50
easy: true
---

# /epic writes agreed: <date> when the user agrees, and the lead's prompts say it never activates an epic alone

Make these changes:
- **commands/epic.md step 5** (:87-88). After the phrase tests/plan_epic_test.sh:90 matches (`Only then, on the user's agreement, set `status: active`; nothing plans a draft epic`), which must stay contiguous, say that the same edit writes `agreed: <YYYY-MM-DD>` (today's date) into the front matter. The skeleton (:29-33) stays `status: draft` with no `agreed:`.
- **commands/epic.md step 3.** On a resume, also delete any `agreed:` line from the epic's front matter, as it already removes `D/agreed`. An epic set back to draft by hand (as #400 was) would otherwise keep its old ticket, and a later draft→active flip would pass the guard with no fresh agreement.
- **The epic format.** In templates/docs/epics/README.md and this repo's copy, board/epics/README.md, add `agreed: 2026-10-23         # set by /epic when the user agrees it` to the front matter block. Under the block, add one sentence: an epic goes `active` only with `agreed:`, a `parent:`, an `hld:` whose agreed HLD grants `epics`, or `lead_epics = on`.
- **commands/swarm.md**, at the gate's draft-epic text (:289-291), away from the never-merge lines that grants-reader (#425) edited. Add one sentence: the lead never sets an epic `active` itself unless one of these holds:
  - an agreed HLD grants `epics` through the epic's `hld:`;
  - `lead_epics = on` in `.claude/swarm/config`;
  - the user agreed the epic through /epic, which writes `agreed:`.

  A split's children carry `parent:`. plan-hld adds its own steps to this file, so keep this story to the one sentence.
- **skills/swarm-dev/SKILL.md** § Why /swarm-dev:swarm stopped (:29-31): add the same clause.

Rules for the text:
- Write the key as bare `lead_epics`. Never write the `swarm.sh config lead_epics` form, which doc_check ties to CONFIG_KEYS before lead-epics-key lands.
- Never name plan-hld (tests/removed_test.sh:38).
- Run the humanizer over the changed text the user sees.

**Done when:**
- tests/plan_epic_test.sh asserts each of these:
  - epic.md step 5 writes `agreed: <YYYY-MM-DD>` alongside `status: active`;
  - epic.md step 3 deletes an old `agreed:` on a resume;
  - templates/docs/epics/README.md names `agreed:`;
  - commands/swarm.md and skills/swarm-dev/SKILL.md each name `lead_epics` and the `epics` grant in the never-activate sentence.

  Each assertion fails on today's text.
- epic-active-on-agreement (:90) still passes.
- doc_check passes.
- `make test` passes.

---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [commands/plan-epic.md:large-epic path, bin/lib/flow_reviewers.py, bin/lib/outcomes_rows.py, tests/]
---

# One critic checks a large epic's split, and the data says whether it pays

Removing /plan-hld (2026-10-17, "fewer parts") left the split of a large epic into child epics with
no adversarial check: the lead writes it alone with one codex pass. Each child is planned in full
later, but no child's skeptics see the whole, so a parent **Done when** item no child covers, or a
`depends_on` order the children cannot build in, passes every child's plan. The user asked
(2026-10-21) for the check and for the data to tell later whether it was worth it.

- /plan-epic's large-epic path starts one `critic` agent (role critic, read-only) on the parent and
  the drafted children before the board PR. It answers: every parent Done when item maps to exactly
  one child (missing and duplicated items named); the children build in their `depends_on` order;
  no child is too big for one full plan. Output `.swarm/<parent>/split-critic.json`
  `{findings:[{kind, why, fix}]}`. The lead fixes or declines each.
- **Its yield:** each finding is logged with `swarm.sh log-finding --reviewer split-critic <kind>
  <board PR URL> "<text>"` (fixed) or `--declined <reason>`, so `flow`'s reviewers section shows the
  split critic's fixed and declined counts and its token cost beside every other reviewer.
- **What it missed (the counterfactual):** when a child's own plan, a later board PR, or a build
  finds a gap that belonged to the split (a parent Done when item no child covers, a missing child
  epic, a dependency order fix), the lead logs it with `--reviewer escaped` and kind `split-gap`
  against the split's board PR. `flow` reports, per split, the critic's fixes against the escaped
  split-gaps, so after a few large epics the numbers say whether the critic catches what matters
  and whether it costs more than it saves.
- commands/plan-epic.md says all three, and `split-critic` and `split-gap` are known reviewer and
  finding names (log-finding refuses unknown reviewers).

**Done when:**
- A stub-agent run of /plan-epic on a large fixture epic starts the critic and writes split-critic.json before the board PR; a medium epic starts none.
- `log-finding --reviewer split-critic` and an escaped `split-gap` both land in events.tsv, and `flow` shows them in the reviewers section for a fixture with one of each (a test asserts both rows).
- commands/plan-epic.md names the critic step and both logging rules, and a test greps them.

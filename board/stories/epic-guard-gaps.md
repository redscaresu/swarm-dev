---
kind: code
status: later
risk: high
depends_on: []
touches: [bin/lib/board.sh:epic_unticketed and next's draft-epic arm, bin/lib/merge.sh:merge_read, commands/swarm.md:lead_epics line]
estimate_lines: 200
easy: false
---

# The epic guard closes the gaps its conductors found

For 0.28 (0.27 retro, 2026-10-25). From conduct-epic-guard's reports (2026-10-24). Split this into one story per gap when it is planned, if it runs over one PR.
- An epic added as `later` (or split, review or done) can be flipped to `active` in a second PR with no ticket.
- A plain `swarm.sh merge` of a story PR that flips an epic from draft to active is not guarded.
- Any new `agreed:` date is accepted. The lead can type one in, and a rename launders a stale one.
- `parent:` is read only at the base, so one PR can demote the parent and add an active child.
- Renaming an already-active epic is refused as unticketed.
- The contents reader is written three times (merge_read, pr_hld, release_check). pr_hld treats any 404 as deleted.
- `next` reports every draft epic as "run /epic", even one with `parent:`, an `epics` grant or `lead_epics = on`. commands/swarm.md reads lead_epics from the config file instead of `swarm.sh config lead_epics`.

**Done when:**
- A test for each gap fails before the fix and passes after it.
- `make test` passes.

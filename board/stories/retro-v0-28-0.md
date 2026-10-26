---
kind: lead
status: ready
depends_on: [release-v0-28-0]
touches: []
---

# Lead: the v0.28.0 retro, with its fixes going into v0.29.0

The user asked on 2026-10-26 for a retro after v0.28.0 rather than one at v0.31.0, so its fixes reach v0.29.0. swarm.sh retro does not exist yet (retro-report, v0.31.0), so the lead runs it by hand. It runs after release-v0-28-0 and before v0.29.0's epics are set active, so their planning reads the changes.

The lead gathers, for the window v0.27.2..v0.28.0:
- every `user-caught` and `lead-hand` intervention in .swarm/events.tsv (29 at the time of writing; the minor ones were left here on purpose when the main ones went into less-noise and merge-holds on 2026-10-26, #562);
- findings: declined out-of-scope with no story, and recurring kinds with no check or a check that does not work (`swarm.sh outcomes`: docs-misstate-code recurred on 23 PRs after its check merged);
- builds: step-ups and holds and why, review rounds per story, test-run times (.swarm/test-runs.tsv), and cost per model (`swarm.sh flow`, cost section);
- what the user had to do by hand, and how long PRs sat green and reviewed but unmerged.

Each item ends as one of: a Done when line in a v0.29.0 epic, a new story, a check, a rule in the builder or conductor brief or AGENTS.md, or dropped with a reason. The lead writes the result to board/retros/v0.28.0.md (items, decisions, where each went) in a board PR, with the v0.29.0 epic edits in the same PR.

**You:** go through the list with the lead and decide each item. The lead learns it is done when you say the list is settled.

**Done when:**
- board/retros/v0.28.0.md is on main, every item in it has a decision, and each "fix" item names the v0.29.0 epic line or story it went into.

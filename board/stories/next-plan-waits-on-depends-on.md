---
kind: code
status: ready
touches: [bin/swarm.sh:next_step (plan-epic loop), tests/next_test.sh, docs/method.md (§ The planning chain)]
---

# next plans an epic only once every epic it depends on is done

next_step's plan-epic loop (bin/swarm.sh:1882-1887) takes the first active epic with no stories and never reads the epic's `depends_on`. On infrafactory (2026-10-14) it named rehearsal-against-the-copy, whose four dependency epics were open, three of them with no stories, while rehearsal-walls, whose dependencies were all done, waited. Its stories would have been scoped against code that did not exist yet. Skip an epic while any slug in its `depends_on` is an open epic or story (reuse open_item, :1928, as unblock does). When every unplanned active epic is skipped this way, fall through as today (nothing to plan), never pick one anyway.

**Done when:**
- tests/next_test.sh: with active epics a (depends_on: [b], no stories) and b (no deps, no stories), next prints `plan-epic b`; with b's file deleted, `plan-epic a`; with b `status: done`, `plan-epic a`.
- The PR shows the first check failing with the depends_on skip removed.
- docs/method.md § The planning chain says an epic is planned once the epics it depends on are done; humanizer ran over the changed prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.
- Runs on macOS's bash 3.2: no mapfile, no associative arrays (AGENTS.md).

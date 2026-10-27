---
kind: code
status: ready
epic: board-pr-and-briefs
depends_on: []
touches: [bin/lib/build.sh:story_brief, bin/lib/build.sh:load_rule, tests/epic_briefs_test.sh:builder brief lines]
estimate_lines: 50
easy: true
---

# Builder brief: selected tests after review fixes, and no self-matching pgrep

story_brief (bin/lib/build.sh:396-437) and load_rule (:290-295) gain two lines. (1) After review fixes, run only the tests mapped to the change and let CI run the full suite: print `scripts/select-tests.sh --run` only when the project has that script, else the project's own tests for the change (v0.28.0: full local runs cost 30 to 60 minutes a round; #560 spent over an hour on two). (2) Never poll with a `pgrep -f` pattern that matches the poll's own command line (two such loops never ended in v0.28.0); find load by its `<slug>-load` marker as load_rule says. The wait-command line is guard-forms-brief's (guard_rule), not this story's.

**Done when:**
- tests/epic_briefs_test.sh renders a builder brief (swarm.sh _brief) in a project with scripts/select-tests.sh and one without, and pins both lines; each check fails when its line is removed, and the project without the script gets no select-tests line.

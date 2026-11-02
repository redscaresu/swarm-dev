---
kind: code
status: ready
epic: machine-usable
depends_on: []
touches: [bin/lib/build.sh:story_brief, bin/lib/build.sh:review_tests_rule, tests/epic_briefs_test.sh:builder brief checks, docs/reference-building.md:builder brief paragraph]
estimate_lines: 40
easy: true
---

# Builders act when their own test run ends and push once their change's tests pass

HLD v0.31.0 addition (HLD:493-496) and #695. The builder brief (story_brief, bin/lib/build.sh:521-563) gains: run a long test run with Bash run_in_background so its end wakes you, and act on it when it ends; before the first push run only the tests mapped to the change (review_tests_rule, build.sh:380-386, today only after review fixes) and push once they pass, leaving the full suite to CI; before you push, stop any test run of yours still going; after the PR opens, push what is ready and put further points in the PR body. No default test cap: ~/.swarm/test-cap stays opt-in. 'Stop any test run of yours still going' names a way the guard allows: kill it by its PID, or stop the background task (the guard refuses pkill and killall).

**Done when:**
- A builder brief built by tests/epic_briefs_test.sh holds each of the four new lines; each check goes red with its line removed from story_brief or review_tests_rule.
- The brief for a tree without scripts/select-tests.sh still names the project's own tests, not select-tests.sh (existing review_tests_rule branch).
- docs/reference-building.md's builder-brief paragraph (line 713-714) says the same.

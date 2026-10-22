---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/build.sh:conduct_brief, tests/build_test.sh]
easy: true
estimate_lines: 60
---

# A conductor starts every ready story of its epic, not only the ones unblock just readied

User, 2026-10-22: "i dont understand why if something is ready you dont just pick it up and work on it". After each merge, the conductor's brief (bin/lib/build.sh:144 and :172) starts only the stories `swarm.sh unblock` prints as `ready:`. unblock prints only the stories it just moved from blocked. A story a board PR adds already `ready` mid-run, as #354 did with codex-test-stray-perl and wait-pr-test-timeout-zero, is never printed, so the conductor never starts it. Both waited about an hour, until the lead told the conductor by hand.

Change both places in the brief, and the backlog conductor's: after every merge, and after reading every inbox note, start each `ready` story in scope that has no build yet and clashes with no running one, whether or not unblock printed it. List them with a swarm.sh call that already exists, or add a `--startable` mode to an existing command, not a new command. docs/reference.md § Merging (line ~1155) says the same.

**Done when:**
- tests/build_test.sh: the conduct brief, epic and backlog, says to start every ready story in scope with no build that clashes with no running one, after a merge and after a note. It no longer limits starts to the stories unblock printed.
- A test with a fixture board, where one story is ready with no build and one is running, shows the command the brief names lists only the first.

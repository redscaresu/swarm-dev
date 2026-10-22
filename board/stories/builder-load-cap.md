---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/build.sh:story_brief, tests/epic_briefs_test.sh]
easy: true
estimate_lines: 30
---

# A builder's brief caps any load or stress run at 4 CPUs and never leaves one running

On 2026-10-22, codex-test-stray-perl's builder reproduced a flaky test under load. It started a Docker container (`stray-perl`, `stress.sh 48 12`) that held all 10 of the user's cores for an hour, and the user's fan ran flat out. Its story asked for "20 runs in a row under load" and set no limit. The lead capped it by hand with `docker update --cpus 4`.

story_brief adds one rule: a builder that loads the machine on purpose (stress loops, parallel test repeats, containers) uses at most 4 CPUs (`docker --cpus 4`, or that many loops), stops and removes what it started as soon as the check ends, never leaves it running between steps, and says in the PR how it loaded the machine.

**Done when:**
- tests/epic_briefs_test.sh: the story brief names the 4-CPU cap, cleaning up straight after, and saying the load in the PR.

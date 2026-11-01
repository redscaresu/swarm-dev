---
kind: lead
status: ready
epic: machine-usable
depends_on: []
touches: []
estimate_lines: 0
easy: false
---

# Lead: Decide the test cap's weight for a selected run

The user's two steps from the epic's Your part. The plan proposes 1/10 of a slot for any run that is not the full suite (filter != all, scripts/test.sh:214-219). Evidence, .swarm/test-runs.tsv read once on 2026-11-01, one project, ended runs with status < 128: selected 820 runs, median 132.5 s, p90 1221 s; full 46 runs, median 3059 s, p90 14260 s. Median ratio ~1/23, p90 ratio ~1/12; 1/10 sits between them and errs toward a selected run weighing more. No story in this plan touches the Makefile or .github/ (scripts/test-map.tsv:27 maps scripts/test.sh to the full suite, no protected path needed).

**Done when:**
- **You:** accept 1/10 or name another fraction (1/k, k a whole number) in this story file before test-cap-weights starts.
- **You:** merge by hand any PR of this epic that touches the Makefile or .github/; none is planned, so check each story's touches lists neither and say so here.

---
kind: code
status: ready
depends_on: []
touches: [bin/lib/reports.sh:log-finding, bin/lib/build.sh:finding_rule, bin/lib/flow_reviewers.py or wherever flow's reviewers section is built, tests/log_finding_test.sh, tests/review_yield_test.sh, docs/reference.md:log-finding and flow entries]
estimate_lines: 120
easy: false
---

# Every finding carries its review round, and flow reports yield by round

Today .swarm/findings.tsv records the reviewer and whether a finding was fixed or declined (with the reason), but not which review round it came from. So no one can see how much each round adds, or check what review-loop-trim saves. The user asked for this data with that change on 2026-10-24.

- `log-finding` takes `--round <n>`. It is optional, so older rows and callers still work. The value goes in a new last column of findings.tsv, and older rows are read as round unknown. The conductor brief tells the conductor to pass the round on every story-PR finding it logs, and `0` for a plan or board-PR finding.
- flow's reviewers section adds a by-round table. For each round n and each reviewer it shows findings fixed, declined by reason, and share fixed. For each story it shows the round its review stopped in and why: a pass with nothing fixed, or merged after fixes.
- Find where flow builds its reviewers section (bin/swarm.sh:477 points at it) and extend that. Fix `touches` in the PR if it is built somewhere else.

**Done when:**
- tests/log_finding_test.sh: `--round 2` writes 2 in the new column, and a row without it still reads.
- A flow test on fixture findings.tsv rows: round 1 with 3 fixed and 2 nits, and round 2 with 0 fixed and 4 nits, report those counts per round. The story shows as stopped in round 2 on a pass with nothing fixed.
- `make test` passes.

---
kind: code
status: blocked
epic: merge-agent-setup
depends_on: [init-merge-allow-rule]
needs: [init-merge-allow-rule: merge_allowed (bin/lib/lifecycle.sh)]
touches: [bin/lib/merge.sh:conduct_stop, bin/lib/build.sh:start_conductor, tests/conduct_preflight_test.sh (new), docs/reference.md:conduct preflight]
estimate_lines: 110
easy: false
risk: high
---

# No conductor starts under merge = agent without the swarm.sh merge allow rule, and next says why

Uses init-merge-allow-rule's merge_allowed. Under merge = agent, conduct_stop (bin/lib/merge.sh:507-532) returns 0 with one line when merge_allowed is false: `no conductor started: merge = agent and no allow rule for swarm.sh merge in <files read>; add <rule> (swarm.sh init checks it)`. So next's conduct_ready (:444-492) says why on each run and starts nothing, instead of a failed conduct event every run. start_conductor (bin/lib/build.sh:1286+) refuses a direct `swarm.sh conduct` with the same line before it writes a brief or opens a pane. Under merge = human nothing changes. A false negative (merge_allowed missing a rule that is there) must never stop conductors silently: the line always names the files read and the rule looked for.

**Done when:**
- tests/conduct_preflight_test.sh (new), merge = agent and a stub CLAUDE_CONFIG_DIR: without the rule, next prints the line, starts no conductor and logs no failed conduct event, and `swarm.sh conduct` exits non-zero with it and creates no workspace or tab (the herdr stub records none); with the rule both get past the check; under merge = human with no rule both get past.
- A false-negative case (the rule written in a form merge_allowed does not read) shows the line on next's output with the files read named, never an empty or silent next.
- Each check fails with the preflight removed, inverted or made silent.

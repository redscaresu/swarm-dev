---
kind: code
status: ready
epic: flow-speedups
depends_on: [merge-agent-ready]
touches: [bin/swarm.sh:start_agent, tests/review_test.sh]
---

# Every agent starts with `gh pr merge` disallowed, a merge = agent conductor too

merge-agent-ready (#177) starts a conductor with `merge = agent` without the `--disallowedTools "Bash(gh pr merge:*)"` guard (bin/swarm.sh start_agent, the `guard=()` line). That conductor merges through `swarm.sh merge`, which runs gh inside the script where the guard never applies, so dropping the guard only lets it also run a bare, unpinned `gh pr merge`. /code-review raised this in all four rounds of #177, and it was declined there only as binding scope. Keep the guard on every claude role whatever `merge` is, and have the conductor's merge = agent rules name `swarm.sh merge` as its only route.

**Done when:**
- tests/review_test.sh: with `merge = agent`, a conductor's start line carries the guard, as a builder's does; with `merge = human` both still do.
- The conduct rules with `merge = agent` say to merge only through `swarm.sh merge`, never `gh pr merge` or `gh api`.
- The PR shows the new check failing with the old `guard` line; shellcheck and every tests/*_test.sh pass.

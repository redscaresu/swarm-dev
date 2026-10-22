---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/agents.sh:agent start env, bin/gh-shim (new), bin/lib/flow_gh_calls.py (new), bin/lib/flow_report.py, tests/gh_calls_test.sh (new), docs/reference.md:Flow and features]
easy: false
estimate_lines: 220
---

# Log every gh call an agent makes, and flow shows who spends GitHub's API budget

User, 2026-10-22: make this part of 0.26. On 0.24.0, both of GitHub's hourly budgets (GraphQL and REST, 5000 each) ran out within minutes of each reset, which stalled every agent for most of the hour. #347 (0.25.0) moved swarm.sh's own polling off GraphQL. But agents also run `gh pr view`, `gh pr checks`, `gh api` and so on by hand, and nothing counts those. Without per-caller numbers, the next fix is a guess.

Agents started by swarm.sh get a `gh` shim first on their PATH (the same way agents.sh:316 passes PATH through). The shim appends one line per call to `.swarm/gh-calls.tsv`: time, agent name (from the env swarm.sh sets), the gh subcommand (`pr view`, `api graphql`, `api <path with ids collapsed>`), whether it uses GraphQL or REST, and its exit code. Then it execs the real gh with the same arguments, stdin and exit code. It never logs arguments beyond the subcommand and the API path, and never a token, body or header. A logging failure never fails the call. swarm.sh's own gh calls are logged too, with the swarm.sh command as the caller. A new `flow` section, gh_calls, prints calls per hour by agent role and by subcommand, GraphQL and REST separately, worst first, with each hour's share of the 5000.

**Done when:**
- tests/gh_calls_test.sh: through the shim, a stub gh's exit code, stdout and stdin pass through unchanged. One line is logged per call, with the subcommand and an API path with its numbers collapsed. No argument after the subcommand appears in the log, checked with a token-like argument. An unwritable log still runs the call.
- `swarm.sh flow` shows gh_calls by role and subcommand from a fixture log.
- The PR quotes gh_calls from this repo after an hour of a running epic on the shim, and names the top three consumers of each budget. If either budget still runs out, it says what follow-up story it filed for the top consumer.

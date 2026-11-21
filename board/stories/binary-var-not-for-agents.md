---
kind: code
status: ready
epic: binary-wrapper
depends_on: []
touches: [tests/env_allowlist_test.sh:pane environment checks, tests/env_allowlist_test.sh:restart wrapper checks]
estimate_lines: 30
easy: true
---

# A test shows no agent gets SWARMDEV_BIN or a SWARMDEV_ handoff name, on a first start or a restart

Needs no other story; tests only. SWARMDEV_BIN names the binary swarm.sh runs, and the SWARMDEV_ handoff names carry a lead's project and die file. Agent starts already drop them: they match no AGENT_ENV, AGENT_SET or AGENT_PREFIXES entry (bin/lib/agents.sh:388-392), on the first start (clean_env through launch_file) and on a restart (resume_file's wrapper keeps only those names, bin/lib/agents.sh:585-640). This story pins both paths with a test. It does not change reserved_env: that would change a rule of the agents' environment while it is bash, which P12 sends through a merge = human window, and would remove a name a board may set, which needs every board checked first (AGENTS.md). A story's env: or the board's agent_env can still name SWARMDEV_BIN; both are the user's to set (contradictions). env_allowlist_test is in macos.yml's SUBSET, so both checks run under bash 3.2.

**Done when:**
- tests/env_allowlist_test.sh: with SWARMDEV_BIN and SWARMDEV_PROJECT exported in the lead's session, the recorded environment of a builder's pane and a conductor's pane holds neither.
- The restart wrapper (resume_file's <session>.py) run with SWARMDEV_BIN and SWARMDEV_PROJECT in its environment drops both, in the style of tests/env_allowlist_test.sh:357-360.
- macos-tests passes on the PR's head.
- Mutation, on a copy of the worktree: add SWARMDEV_ to AGENT_PREFIXES and both checks go red.
- scripts/select-tests.sh --run passes

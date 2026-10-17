---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [env-allowlist-spike]
touches: [bin/lib/agents.sh:start_agent, bin/lib/build.sh:build_story, bin/lib/build.sh:start_conductor, templates/docs/stories/README.md:env row, docs/reference.md:§ agents environment, README.md:§ secrets line, tests/env_allowlist_test.sh (new)]
risk: high
easy: false
estimate_lines: 290
---

# Agents start with an allowlisted environment; a story's env: names anything more, and no value goes through argv

Needs env-allowlist-spike's 'From the spike' paragraph on this story: the launch form, and the variables claude, codex and herdr need. Edits start_agent in bin/lib/agents.sh (bin/swarm.sh:615-676), and build_story and start_conductor in bin/lib/build.sh. start_agent launches every agent kind (builders, conductors, review agents, codex) with only PATH, HOME, TERM, the locale variables, the variables swarm.sh sets and those the spike named. A story's `env: [NAME, ...]` adds those names for its builder; names are checked against [A-Z_][A-Z0-9_]*, and a story never holds values. A conductor gets the allowlist plus the union of its epic's stories' env: names, so the builders it starts can receive them. Values go through a 0600 file that the launch wrapper sources and deletes, never through argv (herdr passes no env, :649-652). Ships on: it is a safety fix. Documented in templates/docs/stories/README.md and reference.md.

**Done when:**
- tests/env_allowlist_test.sh: the herdr stub runs the launch argv under a separate environment holding FAKE_SECRET (the herdr server's); an agent started through start_agent has no FAKE_SECRET, and FAKE_SECRET's value appears in no recorded argv.
- The same test: a builder of a story with `env: [FAKE_SECRET]`, started by a conductor that was itself started through start_agent, receives it, and the values file is gone after launch; `env: [bad-name]` is refused.
- The same test shows PATH, HOME, TERM and the swarm.sh variables reach the agent.

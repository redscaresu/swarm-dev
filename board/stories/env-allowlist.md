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

**From the spike (lead, 2026-10-17, herdr 0.9.1).** herdr has no env option, but `herdr agent start` types the agent's command into the pane's shell, so the agent inherits that shell's environment. The launch form: before `agent start`, swarm.sh sends the pane `exec env -i PATH HOME TERM USER LOGNAME SHELL LANG TMPDIR HERDR_ENV=1 /bin/zsh -f` (each from swarm.sh's own values), plus the story's `env:` names. In a scratch pane with `FAKE_SPIKE_SECRET` exported in the parent shell:
- After the re-exec, `env | grep -c FAKE_SPIKE_SECRET` printed 0 and the shell held 13 variables.
- claude (`--kind claude`): herdr listed it as `claude`, `idle`, `interactive_ready: true`. It answered a prompt, so it was logged in. In its Bash tool, `env | grep -c FAKE_SPIKE_SECRET` printed 0 and `gh auth status` succeeded.
- codex (`--kind codex`, with `-c features.hooks=false`; without it codex stops on a hook-review dialog): herdr listed it `interactive_ready: true`, and a prompt reached the account's usage limit. That shows it was logged in, but the limit stopped it from running the count itself.
- Values for `env:` names: not live-tested. The lead's sandbox denied the `ps` scan. The design: swarm.sh writes the named values to a 0600 file under .swarm/, and sends the pane `set -a; . <file>; rm -f <file>; set +a` before the re-exec's `exec`, so values never appear in argv or in herdr's typed command. This story's tests prove it with a fake: the value is absent from `ps -axww` and from the pane's scrollback, and the file is gone afterwards.
- The re-exec is typed into the pane, so the pane's scrollback shows the variable names but no values.

**Done when:**
- tests/env_allowlist_test.sh: the herdr stub runs the launch argv under a separate environment holding FAKE_SECRET (the herdr server's); an agent started through start_agent has no FAKE_SECRET, and FAKE_SECRET's value appears in no recorded argv.
- The same test: a builder of a story with `env: [FAKE_SECRET]`, started by a conductor that was itself started through start_agent, receives it, and the values file is gone after launch; `env: [bad-name]` is refused.
- The same test shows PATH, HOME, TERM and the swarm.sh variables reach the agent.

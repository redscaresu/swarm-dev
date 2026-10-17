---
kind: lead
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [board/stories/env-allowlist.md:From the spike]
easy: false
estimate_lines: 20
---

# Spike: start a herdr agent with only allowlisted environment variables, and no secret on any command line

A lead story: it needs the user's real herdr and the Claude and codex logins. herdr agent start has only --kind, --pane, --timeout and AGENT_ARG, and swarm.sh notes herdr passes no env (bin/swarm.sh:649-652). In a scratch pane, with FAKE_SPIKE_SECRET exported in the shell that runs herdr, try `herdr agent start ... -- env -i <K=V...> claude ...`, a wrapper script as AGENT_ARG that sources a 0600 values file and deletes it, and a pane shell started under env -i. For each form, check whether herdr still lists the agent with its kind and state, whether claude and codex are logged in, whether the secret is absent, and whether any value shows in `ps` or herdr's command line. Print variable names only, never values. Write the result into env-allowlist's story through a board PR.

**Done when:**
- env-allowlist's story has a 'From the spike' paragraph naming the launch form, every variable claude, codex and herdr need, and how a named value reaches the pane without argv.
- That paragraph quotes, for claude and codex under that form, herdr's agent listing with kind and state, a logged-in reply, and `env | grep -c FAKE_SPIKE_SECRET` printing 0; or it says no form works and why, and env-allowlist is set kind: lead.

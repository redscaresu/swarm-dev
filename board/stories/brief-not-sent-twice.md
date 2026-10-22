---
kind: code
status: ready
depends_on: []
touches: [bin/lib/agents.sh:deliver_prompt, tests/agents_test.sh]
easy: true
estimate_lines: 60
---

# deliver_prompt checks the agent's status before it sends the brief again, and never sends it to a working agent

On 2026-10-22, `swarm.sh conduct --backlog` failed with `the brief was not taken up after 2 attempts (status 'none')`, but the conductor was already working on its brief. Status `none` means the reply from `herdr agent prompt --wait` could not be read, not that the agent was idle. deliver_prompt (bin/lib/agents.sh:681) then sends the brief a second time, so the agent got it twice, and the lead was told the start had failed.

When the status reply is empty or can't be read, check the agent's status on its own first. If it is working or blocked, return success. Send the brief again only if the agent is idle at an empty prompt. The final failure names the last status it read and the reason it gave up.

**Done when:**
- tests/agents_test.sh, with a stub herdr: a prompt reply that can't be read, from an agent whose own status reads working, returns 0 and sends one prompt. An agent idle on both reads gets two prompts, then the failure. A reply of working on the first try sends one.

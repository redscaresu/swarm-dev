---
kind: code
status: blocked
depends_on: [findings-told-sent]
needs: "findings-told-sent: findings_told counting every delivered tell (bin/lib/agents.sh)"
touches: [bin/lib/agents.sh:tell_agent findings branch, bin/lib/lifecycle.sh:step_due, tests/ladder_top_rung_test.sh (new), docs/reference.md:escalate_ladder entry]
estimate_lines: 90
easy: false
---

# A build still drawing real findings on the ladder's top rung goes to the lead

`step_due` (bin/lib/lifecycle.sh, around :790) finds nothing due once a builder is on the top rung, so `tell` keeps sending findings rounds without limit. On 2026-10-24 plan-pr-grant (#441) reached round 7 on fable, with each round raising new gaps of the same kind. The user said on 2026-10-24: escalate when major gaps keep coming after several rounds. Past the top rung, the only step up is the lead. The lead can narrow the scope to something that fails closed, split the story, or accept it with follow-ups.

- Count the findings tells since the builder reached the top rung, the same way `findings_told` counts them. On the 2nd one (that is, the 2nd round on the top rung that still has findings to send), `tell` does not send it. It holds the story for the lead with the existing lead block (`lead_block` and `escalated`: the story turns `kind: lead`, and `reset` and `drop` work on it as today), and writes the findings file into the block. The builder and its PR are kept.
- `next` and `wait --lead` show the held story like any other escalated story.
- A line in docs/reference.md's `escalate_ladder` entry.

**Done when:**
- tests/ladder_top_rung_test.sh (new): with the ladder `sonnet,opus,fable` and a fable builder that has had one findings tell since its step-up, the next findings tell is not sent, and the story is escalated with the findings in its block. On opus, the same tell steps up as it does today.
- `make test` passes.

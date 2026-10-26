---
kind: code
status: blocked
epic: liveness-signals
depends_on: [unsent-brief-resend, no-agent-step-up-marker]
needs: [unsent-brief-resend: the resend that runs first, no-agent-step-up-marker: the .swarm/briefs/<slug>.<kind> marker format and its read in lead_queue]
touches: [bin/lib/lifecycle.sh:resend_pass, bin/lib/lifecycle.sh:lead_queue unsent marker line, commands/swarm.md:wait --lead handler, tests/unsent_brief_test.sh:marker cases, docs/reference.md:the lead wait --lead paragraph]
estimate_lines: 140
easy: false
---

# A brief still unsent after the resend reaches the lead as `unsent brief:`

Uses unsent-brief-resend's bin/lib/lifecycle.sh:resend_pass, its checked record and its `resend` line. Merge after no-agent-alert's marker story, which defines the `.swarm/briefs/<slug>.<kind>` marker family that lead_queue reads (bin/lib/lifecycle.sh:lead_queue) and adds the commands/swarm.md handler-coverage test. On the first poll after a resend, read the still-idle agent's pane once more; if unsent_brief still holds, write `.swarm/briefs/<stem>.unsent` in that family's format, <stem> being the brief's file stem (slug, review-<slug> or conduct-<epic>; build.sh:533,587,1291). deliver_prompt does not write it: it has returned before the resend. lead_queue prints `unsent brief: <stem>, exit: swarm.sh close <stem> then <restart>`: for a builder the restart no-agent-alert's `no-agent:` line names (swarm.sh has no `resume` command on ac61700, so use what that story shipped); `swarm.sh conduct <epic>` for a conductor; `swarm.sh review-agent <slug> <PR URL>` for a review agent. The pass removes the marker when the agent reads working, herdr no longer lists it, or its box is clear. List the line in commands/swarm.md's wait --lead handler (:117-123) and in reference.md.

Review fix (critic, codex): the `.unsent` marker uses the format no-agent-step-up-marker defines, and its line kind joins the wait --lead handler test's kind list. Run the humanizer over the prose this story changes.

**Done when:**
- tests/unsent_brief_test.sh: after a resend, a poll that still reads the paste in s1's box writes .swarm/briefs/s1.unsent, and wait --lead returns printing `unsent brief: s1, exit: swarm.sh close s1 then <the builder restart>`; a review agent's line names `swarm.sh review-agent <slug> <PR URL>`.
- False case: a box clear on the poll after the resend gets no marker, and wait --lead does not return.
- An existing .unsent marker is removed on the poll that finds its agent working or its box clear, and its line is gone from .swarm/lead/seen.
- commands/swarm.md's wait --lead handler lists `unsent brief:` with its exit, and no-agent-alert's handler-coverage test passes.
- reference.md documents the .unsent marker, its line and when it goes.

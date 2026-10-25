---
kind: code
status: blocked
epic: liveness-signals
depends_on: [no-agent-rule]
needs: [no-agent-rule: the herdr agent list read it adds to bin/lib/lifecycle.sh:lead_queue, which the resend pass runs off]
touches: [bin/lib/panes.py:unsent_brief, bin/lib/lifecycle.sh:resend_pass, bin/lib/lifecycle.sh:wait_lead, bin/lib/stall.py:sign_time, bin/lib/agents.sh:stall.py contract comment, tests/unsent_brief_test.sh, docs/reference.md:the lead wait --lead paragraph, docs/reference.md:logs stall rule skipped kinds]
estimate_lines: 230
easy: false
---

# wait --lead submits a brief left in an idle pane's input box, once

Merge after no-agent-alert's core story, which adds one herdr agent list read per poll to wait --lead (bin/lib/lifecycle.sh:lead_queue) and rewrites tests/wait_lead_test.sh's 'it never asks herdr' check (:340); work off that list, never a second herdr agent list. Add unsent_brief(text) to bin/lib/panes.py: true when the pane's input box (the last two border lines at the margin, as pane_stop reads it, agents.sh:944-962) holds `[Pasted text #N`; a submitted prompt above the box does not count. Add resend_pass to wait_lead's poll: for each of this project's agents the list shows idle whose newest start or tell line in events.tsv (story, conduct, review-agent, step-up, tell:*; written once deliver_prompt has returned) is not yet checked, read its pane once with pane_text (herdr agent read, never herdr agent prompt) and record that line as checked under .swarm/lead/. When unsent_brief holds, submit the box with `herdr pane send-keys <pane> Enter` (confirm the key name with `herdr pane send-keys --help`; agents.sh:1386 uses send-keys) and log `resend <name>`. Never resend through tell or deliver_prompt: findings_told counts tell:findings lines (agents.sh:1677-1683), so a second findings tell counts a round twice. Add `resend` to stall.py's sign_time skip list and to the contract comment (agents.sh:50-62). The pass prints nothing and wakes no one. Update reference.md's wait --lead paragraph (:59-66, which says it never nudges an agent) and the stall rule's skipped kinds (:911-916).

Review fixes (critic, codex): runs off no-agent-rule's one herdr list read per poll. An unreadable pane is not a clear input box: retry it on the next poll, and never mark the event checked on a failed read. Submit only when the latest brief was not taken up (no turn started since it was delivered), so an unrelated paste after a finished brief is left alone. Run the humanizer over the prose this story changes.

**Done when:**
- tests/unsent_brief_test.sh: herdr lists s1 idle, its agent read shows `[Pasted text #1 +40 lines]` in the input box, events.tsv has `story s1`: one wait --lead poll sends exactly one send-keys to s1's pane (stub log) and logs one `resend s1`; the next poll, with no new start or tell line, reads no pane and sends nothing.
- False case: s1 idle with an empty box and `> [Pasted text #1 +40 lines]` submitted above it gets no send-keys and no resend line.
- An agent the list shows working, with the paste in its box, gets no agent read (stub log).
- After a `tell:findings` line for s1 and a resend, events.tsv still has one tell:findings line for s1, and stall.py's sign_time returns None for the resend line.
- wait --lead does not return on a resend, and still returns on a held story in the same run.
- reference.md's wait --lead paragraph describes the resend and no longer says it never nudges an agent.
- A test: a pane read that fails once and then shows the unsent brief is resent on the second poll.
- A test: a finished brief followed by an unrelated paste in the input box is not submitted.

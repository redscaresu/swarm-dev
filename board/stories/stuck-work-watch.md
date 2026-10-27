---
kind: code
status: blocked
epic: stuck-work
depends_on: [pane-prompt-classifier, idle-lines-in-lead-queue]
needs: [pane-prompt-classifier: the pane classifier in bin/lib/panes.py, idle-lines-in-lead-queue: lead_queue, the wait --lead handler, KINDS and the wait --lead and method.md lines as it leaves them (shared parts)]
touches: [bin/lib/lifecycle.sh:lead_queue, commands/swarm.md:wait --lead handler, tests/lead_handler_test.sh:KINDS, tests/stuck_work_watch_test.sh (new), docs/reference.md:wait --lead lines, docs/method.md:Every stop names its exit]
estimate_lines: 150
easy: false
---

# wait --lead wakes the lead for an agent stuck on a prompt, a dialog or manual mode

Uses pane-prompt-classifier's classifier (bin/lib/panes.py), and idle-lines-in-lead-queue's lead_queue, handler arm, KINDS and docs lines as it leaves them (shared parts). Re-scoped by less-noise: this story is the `prompt:` line; unmerged-conflict-lines and tell-reads-blocked-pane take the rest of its old text. lead_queue prints `prompt: <agent> (<kind>), exit: <exit>`: a prompt or dialog, the user answers it; manual mode, `swarm.sh restart <slug>`; login, the user runs /login; an API error only once wait has stopped resuming it. Reads stay inside wait --lead's poll budget: the poll's one herdr agent list, and a pane read only for an agent herdr lists as blocked, idle or done. Each wakes the lead once per occurrence. commands/swarm.md's wait --lead handler gets a `prompt:` arm; KINDS gets prompt; docs/method.md's 'Every stop names its exit' names stuck agents. merge-holds' protected-hold-queue also edits lead_queue: story --strict serialises the two.

**Done when:**
- tests/stuck_work_watch_test.sh (new): a blocked agent on each fixture kind gives its prompt: line once; an agent mid-command, and a working agent, give none. It fails with the line removed.
- tests/lead_handler_test.sh passes with prompt in KINDS.

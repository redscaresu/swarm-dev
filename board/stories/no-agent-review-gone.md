---
kind: code
status: blocked
epic: no-agent-alert
depends_on: [no-agent-rule, no-agent-step-up-marker, review-start-unclear]
needs: [no-agent-rule: no_agent_lines in bin/lib/lifecycle.sh and the kind list in tests/lead_handler_test.sh, no-agent-step-up-marker: its edits to no_agent_lines and the commands/swarm.md wait --lead handler, which this story builds on, review-start-unclear: the fixed start reading in bin/lib/agents.sh:deliver_prompt, so a running review agent is not logged as a failed start]
touches: [bin/lib/lifecycle.sh:no_agent_lines review case, commands/swarm.md:wait --lead handler, docs/reference.md:wait --lead paragraph, tests/lead_handler_test.sh:kind list, tests/no_agent_test.sh:review cases]
estimate_lines: 220
easy: false
---

# A PR whose review agent never started, or started and went, reaches the lead

Uses no-agent-rule's no_agent_lines, its herdr list and ps reads, and its tests/lead_handler_test.sh kind list. Comes after no-agent-step-up-marker's edits to the same function and handler, and after review-start-unclear's fix, so a running agent is not logged as a failed start.

For a story with a review start on record for its current PR (.swarm/briefs/review-<slug>.md holds the PR URL), print `no-review: <slug> <pr>, exit: swarm.sh review-agent <slug> <pr>, or the fallback reviewer` when no review-<slug> pane is listed, no round is under way, and one of these holds:
- Never started: the newest `review-agent <slug>` events line is not ok.
- Started and went: that line is ok and .swarm/reviews/<slug>.head was written, but there is no findings file for that head and no `close review-<slug>` line since the start.

A close line is the conductor's own act, as in the 2026-10-25 case. A round is under way while review-<slug> is listed, while a `swarm.sh review-agent <slug>` process runs, or while a `tell:findings` ok line is newer than the newest findings file.

Read files only (build.sh:557-608). Do not use merge.sh:1478-1490's queued_line: it calls gh and stays for conductors. The line fires even when the builder is live. In 0.27.1 the builder sat idle while the conductor ran codex alone (HLD:156-159). Add a `no-review:` arm to commands/swarm.md's wait --lead handler, and add the kind to the handler test's list.

Review fix (codex): review_agent can fail a preflight (reading the PR head, matching the worktree) before it writes `.swarm/briefs/review-<slug>.md`. Read the current PR from the story's `prs:` line or the failed attempt's event, not only from the brief.

**Done when:**
- Tests where it fires, each with the builder listed idle: a review-agent line that is not ok and no review-<slug> pane; an ok review-agent line and a .head, then no pane, no findings file for that head and no close line. Each prints the no-review line with the PR URL and the exit.
- Silent tests: review-<slug> listed; a findings file that passes on its head (review_pass); a tell:findings ok line newer than the findings file; a `swarm.sh review-agent <slug>` process running; the 2026-10-25 `close review-config-keys-back` events replayed.
- A test runs the exit (`swarm.sh review-agent <slug> <pr>`, stubbed): it starts review-<slug>, and the next poll is silent.
- The call-count test with this case present still counts one herdr list, no herdr agent read and no gh call.
- `no-review` is on tests/lead_handler_test.sh's kind list, and the test goes red when its arm is removed.
- reference.md names the line and its exit. The humanizer ran over the changed reference.md and commands/swarm.md prose, and the PR says so.
- A test: a review-agent start that fails its preflight before writing the brief, with the PR open and no round under way, fires `no-review:`.

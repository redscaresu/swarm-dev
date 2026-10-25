---
kind: code
status: ready
epic: no-agent-alert
depends_on: []
touches: [bin/lib/lifecycle.sh:no_agent_lines (new), bin/lib/lifecycle.sh:no_agent_exit (new), bin/lib/lifecycle.sh:lead_queue, bin/lib/lifecycle.sh:lead_wake, commands/swarm.md:wait --lead handler, docs/reference.md:wait --lead paragraph, tests/wait_lead_test.sh:herdr stub and the never-asks-herdr case, tests/no_agent_test.sh:population cases (new file), tests/lead_handler_test.sh:kind list (new file)]
estimate_lines: 300
easy: false
---

# wait --lead wakes the lead for a started story with no live agent

Add no_agent_lines and no_agent_exit to bin/lib/lifecycle.sh. no_agent_lines makes no gh call. It reads one `herdr agent list` (lead_wake takes it once per poll), one `ps -A -o command=` (match only, never print: arguments may hold a token) and files. It prints `no-agent: <slug>, exit: <exit>` for each story that meets all of these:
- It has a build record (build_started, lifecycle.sh:805-808, or build_exists, board.sh:1058).
- It is status ready, or review under merge = agent.
- It is not held_for:, escalated, kind: lead or blocked.
- waiting_on_user does not route it to the user (board.sh:966-967: awaiting your merge under merge = human or costs money, or kept:), green or not.
- No live agent: herdr lists no pane in own_panes (agents.sh:70) named agent_name of <slug> or review-<slug> (swarm.sh:427-433 cuts names), and no `swarm.sh wait-pr` or `swarm.sh merge` process runs for a URL on its prs: line.
- No tell pending: no `swarm.sh tell|story|review-agent|step-up|_step-up|restart <slug>` process runs. The event that answers a tell is that command's own events.tsv line, written when it exits (swarm.sh:891-943).
- No `hold <slug>` line since the alert's event. That is the lead's acknowledgement, with a reason.
- No .swarm/briefs/<slug>.step-up marker. no-agent-step-up-marker reports those.

no_agent_exit gives the exit. For a ready story it is `swarm.sh hold <slug> <reason>`; restart-builder adds `swarm.sh restart <slug>, or ` in front. For a review story it is `swarm.sh merge --head <the head: line of .swarm/reviews/<slug>.md> <pr>`. With HERDR_ENV unset or herdr's list failing, no_agent_lines prints nothing.

lead_queue appends no_agent_lines. lead_wake logs `lead-woken <slug>` with the kind in the outcome (`ok (no-agent)`). It cuts the slug at the comma; today lifecycle.sh:1857 cuts at the first space. A pane can go with no close line or failed start to explain it. Then the first poll that sees it writes a `no-agent <slug>` events.tsv line, and only a later poll wakes. The quiet first read with no LEAD_SEEN (lifecycle.sh:1920) still prints no-agent lines.

commands/swarm.md's wait --lead handler (:117-123) gets a `no-agent:` arm that runs the exit. A new tests/lead_handler_test.sh drives lead_queue to each kind on its kind list and fails when the handler has no arm for one. `kept` is on the list as the one known gap; kept-handler-arm closes it. tests/wait_lead_test.sh:340 ('it never asks herdr') becomes 'one herdr agent list per poll, no per-pane read', and keeps its guard that a running conductor cannot hide the queue. reference.md § The lead (:59-63) names the line, the population, the tell rule, the hold acknowledgement and the exits. liveness-signals' resend story reuses the list read, so keep it reachable from wait_lead.

Review fix (codex): `swarm.sh hold` only logs an event and starts nothing, so a hold line must not silence the alert for good. A held story stays silent only while the hold's reason is current: the alert comes back once a builder or review agent is gone again after the hold, or on the next poll after the hold's own event if no agent was restored.

**Done when:**
- Tests where it fires: a ready story with a build record whose builder pane went after a close line (it wakes on the next poll); a pane gone with no close line (the poll that writes the `no-agent` events line does not wake, the next poll does); a review story under merge = agent with no agent and no merge or wait-pr process, whose exit names `swarm.sh merge --head`.
- Tests where it stays silent: a ready story not started (queued on capacity, a clash or a depends_on); the CI window after a push (builder listed idle, review agent closed); the 2026-10-25 `close review-config-keys-back` events replayed with the builder listed; a review story waiting on the user whose head is still pending under merge = human; a held story; a kind: lead story; herdr's list failing; a review story with a `swarm.sh merge <url>` process running.
- Tell tests: with a `swarm.sh tell <slug>` process running and the builder not listed (pending), it is silent; with that process gone, an ok tell line and the builder listed (answered), it is silent; with an ok tell line and then the builder's pane gone (pane gone after the answer), it fires.
- A test: `swarm.sh hold <slug> <reason>` after the alert silences it until a new event for the slug.
- A test: a fresh run with no .swarm/lead/seen prints the line on its first read.
- Stub logs show each poll makes one `herdr agent list`, no `herdr agent read`, and no gh call from no_agent_lines. The rewritten wait_lead_test.sh:340 case fails if a second list call is added.
- tests/lead_handler_test.sh goes red when the `no-agent:` arm is removed from commands/swarm.md.
- reference.md names the line, the population, the tell rule and the exits. The humanizer ran over the changed reference.md and commands/swarm.md prose, and the PR says so.
- A test: after `swarm.sh hold` on a started story whose builder is gone, the next poll with still no agent fires `no-agent:` again; a hold followed by a restored builder stays silent.

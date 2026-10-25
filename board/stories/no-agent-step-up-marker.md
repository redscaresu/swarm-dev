---
kind: code
status: blocked
epic: no-agent-alert
depends_on: [no-agent-rule]
needs: [no-agent-rule: no_agent_lines and lead_wake in bin/lib/lifecycle.sh, and the kind list in tests/lead_handler_test.sh]
touches: [bin/lib/lifecycle.sh:no_agent_lines marker read, bin/lib/lifecycle.sh:start_rung failure line, bin/lib/lifecycle.sh:step_up_failed, bin/lib/lifecycle.sh:close_agent step-up partway message, bin/lib/agents.sh:tell_agent step-up partway message, bin/lib/build.sh:conduct_brief escalate_ladder paragraph, commands/swarm.md:wait --lead handler, docs/reference.md:marker files, tests/lead_handler_test.sh:kind list, tests/no_agent_test.sh:marker cases, tests/epic_briefs_test.sh:step-up text, tests/escalate_triggers_test.sh:step-up failed text, tests/close_test.sh:step-up partway text]
estimate_lines: 200
easy: false
---

# A failed step-up reaches the lead within one poll; one under way stays silent

Uses no-agent-rule's no_agent_lines and lead_wake (bin/lib/lifecycle.sh) and its tests/lead_handler_test.sh kind list. step_up writes .swarm/briefs/<slug>.step-up when it begins (lifecycle.sh:622) and removes it only on success (:748), so a marker alone is not a failure. A step-up can stop after closing the builder and keep the marker: start_rung's failures (:698-745) and step_up_failed (:791-796). At each of those points, write a `step-up:failed <slug> ok (<why>)` events.tsv line; flow reads only ok lines (flow_lead_queue.py:97).

no_agent_lines reads `.swarm/briefs/<slug>.<kind>` markers with no herdr or gh call. It prints `step-up failed: <slug>, exit: swarm.sh step-up --resume <slug>` when three things hold: the marker is there, the newest step-up line for the slug is step-up:failed, and no step-up of it is running (its .swarm/locks/step-up-<slug> lock or a step-up process). Document the marker format in reference.md (path, first line, the failure line that arms it, the lead line, the exit), so liveness-signals' `.unsent` marker uses the same format.

The conductor no longer lists a failed step-up. Rewrite these texts to say the lead is told through wait --lead and the story is left alone: conduct_brief's escalate_ladder paragraph (bin/lib/build.sh:954-955), step_up_failed (lifecycle.sh:794), close_agent (:514) and tell_agent (agents.sh:1630). Add a `step-up failed:` arm to commands/swarm.md's wait --lead handler, and add the kind to the handler test's list.

**Done when:**
- Tests where it fires: a marker, a step-up:failed line and no builder. wait --lead prints the line within one poll. A fresh run with no .swarm/lead/seen prints it on its first read.
- Silent tests: a step-up under way (the marker, no failure line, no builder listed, its step-up running), and the state after a resume that worked (marker gone).
- A test finds the ok step-up:failed line in events.tsv for each failure point.
- The call-count test with a marker present still counts one herdr list and no gh call.
- tests/epic_briefs_test.sh pins the new conduct_brief text and fails if it again says to list a failed step-up for the lead. tests/escalate_triggers_test.sh and tests/close_test.sh pin the new partway messages.
- `step-up failed` is on tests/lead_handler_test.sh's kind list, and the test goes red when its arm is removed.
- reference.md documents the marker format. The humanizer ran over the changed reference.md and commands/swarm.md prose, and the PR says so.

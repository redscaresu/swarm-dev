---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [tell-refusal-state, flow-start-failures]
needs: [tell-refusal-state: the state= field on refused tell lines (bin/lib/agents.sh:tell_agent, tell_gone), flow-start-failures: tests/flow_sections_test.sh:section lists and docs/reference-logs.md's section list and flow row, which it edits first]
touches: [bin/lib/flow_tell_refusals.py (new), tests/flow_tell_refusals_test.sh (new), tests/flow_sections_test.sh:section lists, docs/reference-logs.md:flow section list (Flow and features), docs/reference-logs.md:tell_refusals paragraph (new, Flow and features), docs/reference-logs.md:flow row (Commands), bin/lib/reports.sh:tell_refusals doc comment (new)]
estimate_lines: 200
easy: false
---

# flow tell_refusals: refused tells by pane kind and state, and could-not-reach per target

From tell-refusal-state it uses the state= field tell_agent and tell_gone write, and a real refused tell for its end-to-end case; from flow-start-failures, the section lists in tests/flow_sections_test.sh and docs/reference-logs.md (Flow and features, the flow row) it added start_failures to. New bin/lib/flow_tell_refusals.py over tell and tell:<kind> lines in the window: tells and refusals (outcome() not ok and not queued:/replaced:) by pane kind (agent: the target's agent name has an .swarm/agents.tsv line; other) and state (`-` for a row with no state=: an old row, or a refusal before the state was read, and the docs say so); then, after a blank line, `could not reach` refusals per target. Goal 2's bars read it: agent-pane refusals over agent-pane tells, and no target above 1.

**Done when:**
- tests/flow_tell_refusals_test.sh (new), fixture: refused tells to an agent in agents.tsv and to a name not in it count under agent and other, by state; ok, queued: and replaced: lines count as tells, not refusals; a refused row with no state= counts under `-`.
- A target refused `could not reach` twice shows 2 in the per-target table.
- End to end: a tell refused by a real swarm.sh tell in a fixture project (herdr stubbed as tests/tell_blocked_test.sh does) shows under its state.
- tests/flow_sections_test.sh passes with tell_refusals in both lists.
- Copy-aside proof: dropping the agents.tsv lookup turns the agent-pane case red.
- docs/reference-logs.md lists tell_refusals with what each column means; tests/doc_check_test.sh passes.

---
kind: code
status: ready
epic: liveness-signals
depends_on: []
touches: [bin/lib/panes.py:test_running, bin/lib/agents.sh:test_running, bin/lib/agents.sh:agent_stalled, bin/lib/agents.sh:pane_quiet, bin/lib/agents.sh:herdr_wait agent_stalled call, bin/lib/agents.sh:settle agent_stalled call, tests/agent_liveness_test.sh:wait --stall process-tree cases, docs/reference.md:stall_minutes setting, docs/reference.md:wait stuck and stalled, docs/method.md:settings table stall_minutes row, tests/escalate_triggers_test.sh:no step-up during a test run]
estimate_lines: 200
easy: false
---

# A test run in an agent's pane is work: wait never reads it as stalled or stuck

Add test_running(<herdr pane process-info JSON>) to bin/lib/panes.py: take shell_pid and one `ps -A -o pid=,ppid=,command=` read (as longest_child.py:30-60 does) and return true when a process under that shell (ppid walk) runs a suite: make with a `test` argument, or a shell or the script itself running scripts/test.sh. Patterns in one constant; never print a command or argument (they may hold a token). Any read failure returns false, so today's stall still fires. Add test_running <target> to agents.sh beside bg_running (one herdr pane process-info call; python3 -I with SWARM_LIB). agent_stalled takes the target as a third argument (its callers herdr_wait and settle have it) and returns 1 when test_running, checked only after both age passes reach stall_minutes, so a live agent costs no extra call. pane_quiet returns 1 when test_running, after bg_running. agent_stalled never fires for a conductor (agents.sh:1162-1164), so a conductor's half is pane_quiet. Never read the run marks (.swarm/test-runs*) and never change scripts/test.sh (test-speed's). In tests/agent_liveness_test.sh move the stalled and named-leaf cases (:228-263, a hung sleep under make test) to a tree whose sleep sits under a non-test command, then add the test-run cases. Rewrite reference.md's stall_minutes bullet (:292, whose make-test example no longer stalls) and the stuck/stalled text (:606-622), and method.md's stall_minutes row (:125).

Review fixes (critic, codex): count `make check` as a test run too (swarm.sh init makes it the gate in other projects). Test pane_quiet for a builder as well as a conductor (`stuck: no output` with and without a run). Extend tests/escalate_triggers_test.sh: with escalate_ladder set, a builder running make test past stall_minutes is not stepped up. Run the humanizer over the prose this story changes.

**Done when:**
- tests/agent_liveness_test.sh: `wait --stall` on a busy builder past stall_minutes prints no `stalled:` and does not exit 3 when its pane tree holds `make test`, and again with only `bash scripts/test.sh`; the same tree with the run removed prints `stalled:` and exits 3.
- `wait conduct-<epic>` on a busy conductor whose pane has not changed for stall_minutes exits 4 with `stuck: no output` with no test run in its tree, and does not exit 4 with `make test` under its pane shell.
- A tree where test.sh or test is only an argument (`grep scripts/test.sh`, `cat test`) is no test run: the builder still stalls.
- With herdr pane process-info printing nothing, or ps failing, the builder with a test run still stalls (exit 3).
- The moved named-leaf cases still name the hung leaf by program name, with no argument (SEKRIT) in the output or events.tsv; tests/escalate_triggers_test.sh and tests/dash_stalls_test.sh pass with no assertion removed or loosened.
- reference.md and method.md say a test run in the agent's pane is work for `wait --stall` and for `stuck`.
- A builder with `make check` in its pane tree is not stalled, and without it is.
- pane_quiet: a builder past stall_minutes with make test in its tree gets no `stuck: no output`; without it, it does.
- tests/escalate_triggers_test.sh: a builder running make test past stall_minutes, with escalate_ladder set, is not stepped up.

---
kind: code
status: blocked
epic: port-checks
depends_on: [diff-run-core]
needs: diff-run-core (tests/diff_run.sh: the fixture format with stdin, the shims, the group wait)
touches: [tests/diff_run.sh:hook env and seq mask, tests/diff_fixtures_hooks.sh, tests/diff_run_hooks_test.sh]
estimate_lines: 220
---

# The differential run takes the hooks, fed their JSON on stdin

Uses diff-run-core's fixture format with stdin and its shims. Fixtures for the four hooks hooks/hooks.json runs, each fed its JSON on stdin as tests/merge_guard_test.sh:49,56 does: merge-guard refusing a raw PR merge and passing `ls`; lead-stop on a Stop, with next naming a step and with none; agent-state.sh working and idle; user-caught-reminder in the lead's session and in an agent's. The hook env sets CLAUDE_PLUGIN_ROOT to the tree and keeps SWARM_FORBID_PROJECT off every fixture project, or the hooks write no event line (hooks/merge-guard.sh:23,704-717; hooks/lead-stop.sh:24,94-100). agent-state's fixtures set SWARM_AGENT, HERDR_PANE_ID and a SWARM_RESUME file whose --resume names the fixture's session_id, so each reaches its herdr call (hooks/agent-state.sh:24). Its --seq is time.time_ns() (hooks/agent-state.sh:28,58,60): the run masks the value after --seq in herdr calls by its shape and compares the rest of the argv. Each fixture names the stub calls it must make, and one that makes none of them in either tree is red, so an early exit cannot pass.

**Done when:**
- (1) Two copies of one tree compare clean on every hook fixture, and so do v0.31.2's tree and v0.31.3's (neither changed hooks/), each fixture making its named calls. (2) In one copy each of these is red, naming the hook fixture: merge-guard's exit code; one byte of lead-stop's stdout; one byte of merge-guard's event line; one extra herdr call from agent-state; one byte of agent-state's herdr argv outside --seq. (3) With SWARM_FORBID_PROJECT exported by the caller, as make test does, merge-guard's refusal still writes its event line in both trees, and dropping it from one tree is red. (4) An agent-state fixture with its SWARM_RESUME file removed is red, since its herdr call is missing. (5) If diff-run-order is on main when the PR opens, every hook fixture also compares clean under `--times 3`. (6) tests/diff_run_hooks_test.sh runs in under 120 s on its CI shard.
- scripts/select-tests.sh --run passes

---
kind: code
status: blocked
epic: port-checks
depends_on: [diff-run-core, speed-margin]
needs: diff-run-core (tests/diff_run.sh's fixture loader and stubs); speed-margin (the margin from your You: step)
touches: [tests/speed_run.sh, tests/speed_list.txt, tests/diff_fixtures_dash.sh, tests/speed_run_test.sh]
estimate_lines: 260
---

# A speed run reports wall time and process starts per command for two trees and fails a slower one

Uses diff-run-core's fixture loader and stubs, and the margin from speed-margin: the user set it on 2026-11-20 to 20%, with a 100 ms floor (a gap under 100 ms never fails the job). Process starts are reported and never fail the job. tests/speed_run.sh <tree-a> <tree-b> runs each fixture on tests/speed_list.txt N times per tree, alternating trees, with SWARM_SLEEP_SCALE and SWARM_DASH_NOW fixed. Per command it reports each tree's median wall time and process starts, and it fails a command whose tree b median is over tree a's by the margin, a named constant. Every list entry must name a fixture; an unknown one is red, never skipped. The list starts with next, status, dash and usage; port epics add theirs. No fixture covers dash yet, so this story adds fx_dash in tests/diff_fixtures_dash.sh: board, agents and PRs stubbed, SWARM_DASH_NOW fixed, no detached refresh. Process starts are counted by a method its header names (for example strace -f -e trace=execve). Where it cannot count, the report says `not measured`, never 0, and `--require-count` fails instead. No timing on the lead's machine: the local test runs at most 3 repeats, and its seeded slowdown is an external /bin/sleep, which SWARM_SLEEP_SCALE does not shrink (bin/lib/agents.sh:1815-1818).

**Done when:**
- (1) Two copies of one tree pass. (2) A copy with a /bin/sleep longer than the margin seeded into one command fails that command only. (3) A copy with one extra external exec in a command (/usr/bin/true, since bash's true is a builtin) reports exactly one more process start where counting works and `not measured` where it does not, and there it fails under `--require-count`. (4) An unknown list entry is red. (5) fx_dash compares clean in tests/diff_run.sh on two copies. (6) tests/speed_run_test.sh checks (1)-(4), with proofs on a worktree copy without .git, in under 120 s on its CI shard.
- scripts/select-tests.sh --run passes

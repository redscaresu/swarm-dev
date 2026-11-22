---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [tests/diff_fixtures_ci_gate.sh]
estimate_lines: 200
---

# Tests-only: differential fixtures that run ci_gate through wait-pr, review-agent --recheck, status and next

Tests-only. The switch's differential run must be clean for the merge, wait-pr, review-agent, status and next fixtures (parent Done when). Only the merge fixtures reach ci_gate today: next and status run on an empty project (tests/diff_fixtures_cmds.sh:18-19), and no fixture runs wait-pr or review-agent.
Adds tests/diff_fixtures_ci_gate.sh, whose fixtures each run ci_gate: wait-pr on a green and on a pending head (merge.sh:2606); review-agent --recheck on a green head (build.sh:1118); status with an open story PR whose head and files it reads (board.sh:3415, :2609); next with a queued story, whose queued: line runs ci_gate age (merge.sh:3200 through board.sh:1050). It reuses tests/merge_fixture.sh's stubs and edits no other file. No speed_list.txt or nopy_list.txt line: nothing is ported here.

**Done when:**
- (1) Each new fixture's recorded gh calls include the check-runs read ci_gate makes on its head (`api --paginate repos/o/r/commits/<sha>/check-runs?per_page=100`). (2) tests/diff_run.sh with main as both trees is clean for every new fixture, ten runs. (3) tests/diff_run.sh of the worktree against a copy without .git where ci_gate.py's judge() calls one green check pending is red, naming each new fixture; the PR quotes it. (4) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

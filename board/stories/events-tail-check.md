---
kind: code
status: blocked
epic: telemetry-readers
depends_on: [outcome-readers-dash, outcome-readers-flow, outcome-readers-lead, outcome-readers-merge, outcome-readers-agents, events-outcome-helper, events-fixture]
needs: [outcome-readers-dash, outcome-readers-flow, outcome-readers-lead, outcome-readers-merge, outcome-readers-agents: every reader these commands cross already on the helper, events-fixture: tests/fixtures/events/v029-sample.tsv and tests/events_tail_helpers.sh (a stand-in project from an events file, its tailed copy, same_output), events-outcome-helper: SEP, to build the tail]
touches: [tests/events_tail_test.sh (new), tests/dash_projects_test.sh:predating case (new)]
estimate_lines: 130
easy: false
---

# Whole commands read the same over the fixture with and without a tail

Needs every wave-2 reader story merged: dash --check, dash and wait --lead each run readers from several of them. Needs from events-fixture: the fixture, the tailed copy and same_output. Needs from events-outcome-helper: SEP for the tail. New tests/events_tail_test.sh diffs whole commands over the fixture project and its copy with `<SEP>k=v` on every row: `dash --check` and one `wait --lead` pass (herdr and gh stubbed). tests/dash_projects_test.sh gains the epic's case: a project whose files predate the fields (the untailed fixture) and its tailed copy, drawn by one `dash --project`, give the same panel. The epic's mutation proof: one shell and one Python reader these commands run, put back on an exact compare in a worktree copy without .git, turn it red.

Read the lead's queue through lead_queue (lifecycle.sh), not `wait --lead`, which blocks and writes. Keep each new test file under TEST_FILE_TIMEOUT: a Makefile SLOW entry is a protected path.

**Done when:**
- events_tail_test.sh: `dash --check` exits 0 over both projects and prints the same; lead_queue (the function `wait --lead` reads) prints the same non-empty lines over both, at least one untailed.
- dash_projects_test.sh: `dash --project <untailed> --project <tailed>` draws the same panel lines for both apart from the project name, with a non-empty Recent box.
- In a worktree copy without .git, one shell and one Python reader these commands run, put back on `$5 == "ok"` / `f[4] == "ok"`, each turn events_tail_test.sh or dash_projects_test.sh red; the PR keeps the FAIL lines.
- No test file this story adds runs `swarm.sh wait --lead`, and each runs under TEST_FILE_TIMEOUT in CI.

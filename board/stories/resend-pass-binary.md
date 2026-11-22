---
kind: code
status: later
epic: helpers-shared
depends_on: [go-resend-rows, shared-copies-list]
needs: go-resend-rows: the _resend-rows entry and its marker. shared-copies-list: docs/port/copies.tsv's resend_pass row, deleted here.
touches: [bin/lib/lifecycle.sh:resend_pass, docs/port/sites.tsv:resend_pass row, docs/port/copies.tsv:resend_pass row, docs/port/swarm-names.tsv:SWARM_PANES row, docs/port/swarm-names.tsv:SWARM_BACKLOG row, docs/port/swarm-names.tsv:SWARM_NAME_MAX row, docs/port/swarm-names.tsv:SWARM_BRIEFS row, tests/diff_fixtures_resend.sh, tests/events_tail_lead_test.sh:tell_resend, tests/lead_queue_wait_test.sh:resend_pass checks, tests/speed_list.txt:resend_delivery line]
estimate_lines: 160
---

# resend_pass gets its rows from the binary's _resend-rows entry

Needs the _resend-rows entry from go-resend-rows, and resend_pass's row in docs/port/copies.tsv from shared-copies-list. resend_pass (bin/lib/lifecycle.sh:4828) runs `binary_run _resend-rows` in place of python3 at :4838, with the same inputs. It keeps `2>/dev/null)" || return 0` and the fast path that starts no process (:4834). The call sits in a $(...), so with no binary the die ends only that subshell and the pass does nothing this poll, as a failed python3 leaves it today. The rows body is Go in a rules package, which internal/layers keeps from starting any process; that is P13's check for the ported body. panes.py's call at :4939 stays, helpers-panes', so no check runs resend_pass whole with python3 failing. SWARM_PANES, SWARM_BACKLOG, SWARM_NAME_MAX and SWARM_BRIEFS are no longer set there; their rows in docs/port/swarm-names.tsv lose lifecycle.sh, or go when no file names them. tests/events_tail_lead_test.sh (tell_resend) and tests/lead_queue_wait_test.sh call resend_pass with bin/lib sourced and no swarm.sh. They stay green, edited only as far as the call needs, since they are port-reports' rows. Delete the site's events_outcome row in docs/port/sites.tsv (:28; the panes row :29 stays) and its row in docs/port/copies.tsv.

**Done when:**
- (1) tests/diff_run.sh --base <base> is clean on fixtures in tests/diff_fixtures_resend.sh that run wait --lead with a herdr stub and the real panes.py: an idle agent with a new delivery whose box holds the paste (the Enter goes), one in after mode, markers for an idle, a gone and a working agent, a tell line, the backlog conductor, and one where herdr fails every pane read. The base tree runs the inline program, so this is the comparison with it. tests/speed_list.txt names fx_resend_delivery. (2) The run goes red with go-resend-rows' marker removal broken, shown on a worktree copy without .git. (3) tests/port_sites_test.sh passes with the events_outcome row deleted, and goes red on a copy with the inline program put back. (4) A check in tests/lead_queue_wait_test.sh runs resend_pass with SWARMDEV_BIN naming a missing file: it returns 0 and reads no pane. (5) tests/events_tail_lead_test.sh, tests/lead_queue_wait_test.sh, tests/port_copies_test.sh and tests/port_swarm_names_test.sh pass. (6) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

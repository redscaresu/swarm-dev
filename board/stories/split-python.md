---
kind: code
status: ready
epic: swarm-sh-split
depends_on: []
touches: [bin/swarm.sh (whole file), bin/lib/*.py (new), .github/workflows/ci.yml:test job, tests/*_test.sh:paths read]
easy: false
estimate_lines: 2300
---

# Move swarm.sh's 19 python heredocs and 4 python modules into bin/lib/*.py

A pure move, exempt from the size cap (the estimate counts moved lines), and the first story of all. Each `python3 - <<'PY'` body (19, listed in survey.json) becomes bin/lib/<bash function>.py, called as python3 "${SWARM_HOME}/bin/lib/<f>.py" with the same args and env (SWARM_HOME, bin/swarm.sh:68). outcomes_report's two heredocs become outcomes_rows.py (:1107-1246) and outcomes_join.py (:1273-1337). PANES_PY, STALL_PY, REPORT_PY and DASH_LEGEND_PY (:336,438,848,4859) become panes.py, stall.py, report.py and dash_legend.py, imported through sys.path in place of exec(os.environ[...]) (:925 and the other exec sites). No other python changes. Tests that read swarm.sh text (agent_state_test:88, config_test:127, epic_test:135/1011/1019, fail_lines_test:185, next_test:626, removed_test:18, roles_test:13/28) change only which files they read. ci.yml's test job gains a py_compile step (no new required context).

**Done when:**
- grep finds no `python3 - <<` and no `exec(os.environ` in bin/swarm.sh.
- `python3 -m py_compile bin/lib/*.py` passes, and ci.yml's test job has that step.
- A check quoted in the PR body shows each .py file equals its heredoc at the base commit apart from import lines, and names bin/lib/outcomes_rows.py and bin/lib/outcomes_join.py.
- Every tests/*_test.sh passes, and the diff to tests/ changes only the paths they read.

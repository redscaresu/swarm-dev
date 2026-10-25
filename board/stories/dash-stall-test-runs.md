---
kind: code
status: blocked
epic: liveness-signals
depends_on: [stall-counts-test-runs]
needs: [stall-counts-test-runs: test_running in bin/lib/panes.py and bin/lib/agents.sh, which dash reuses]
touches: [tests/dash_stalls_test.sh:stall cases, docs/reference.md:stall_minutes setting, bin/lib/dash.sh:herdr reads, bin/lib/dash_render.py:agent rows stall rule]
estimate_lines: 90
easy: false
---

# dash shows an agent running tests as working, not stalled

Uses stall-counts-test-runs' bin/lib/panes.py:test_running. dash_render.py has its own stall rule (:271-281): an agent whose stall_age reaches stall_minutes shows `stalled <N>m`, is marked ! and is listed as `look at` under needs you. For such an agent only (age already past the threshold, so most redraws make no call), read herdr pane process-info for its pane and call test_running; a run in its tree shows `working <N>m` with no look-at line, builder or conductor. A failed read leaves it stalled. Add dash to the sentence stall-counts-test-runs wrote in reference.md's stall_minutes bullet.

Review fix (critic): dash.sh does every herdr read today (bin/lib/dash.sh:535-538), so read process-info there and pass the result to dash_render.py; dash_render.py makes no herdr call. tests/dash_stalls_test.sh is SERIAL, so this is not an easy story.

**Done when:**
- tests/dash_stalls_test.sh: s-three, 2 hours with no sign of life, shows `working` and no `look at s-three` when the herdr and ps stubs put `make test` under its pane shell, and still shows `stalled 1(19|20|21)m` and `look at s-three` without it; a conductor past the threshold does the same.
- A working agent under stall_minutes gets no herdr pane process-info call during dash (the herdr stub's log shows none).
- With process-info failing, the existing stalled assertions pass unchanged.
- dash_render.py makes no `herdr pane process-info` call (the herdr stub's log shows process-info calls only from dash.sh); its existing `herdr agent read` through shown_state is unchanged.

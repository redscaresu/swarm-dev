---
kind: code
status: later
epic: conductor-hands-off
depends_on: []
needs: [less-noise's name-cut-helper: the exact-record name cut (bin/lib/lifecycle.sh close_panes, close_epic, cut_live); the epic's constraint orders this story after it, and the lead adds depends_on once the slug is final]
touches: [bin/lib/dash_render.py:reported, bin/lib/flow_idle_slots.py:event keys and conductor_runs, tests/exact_names_test.sh (new)]
estimate_lines: 120
easy: false
---

# flow idle_slots and dash's reported conductors key agents by exact name

Two lanes-review items. (1) dash_render.py's reported() (bin/lib/dash_render.py:169-172) guesses the epic from the conductor's name (`base[len('conduct-'):]`) when epic_of has no entry, as once the epic file has left the board; a name cut at 32 characters gives a wrong report path, so a reported conductor shows as working. Take the epic from the conductor's own record (DASH_EVENTS' conduct line or DASH_AGENTS_LOG) by exact name; with none, do not guess. (2) flow_idle_slots.py keys readies, reviews, closes and stops by agent_name, the 32-character cut (bin/lib/flow_idle_slots.py:98-135), so two slugs that share their first 32 characters merge into one key. Key by the full slug where the record has it, and conductor_runs by the exact conductor name. The epic's Area names bin/lib/dash_finished.py; that file has no conductor or report path. Merge after less-noise's name-cut-helper (lifecycle.sh close_panes, close_epic, cut_live); use its exact-name rule, and its helper if the Python can call it.

Held as later until less-noise is planned: it then gets depends_on less-noise's name-cut story (it uses the exact-record name cut).

**Done when:**
- tests/exact_names_test.sh (new): a conductor of an epic whose `conduct-<epic>` is longer than 32 characters, its epic file gone and its report written, shows in dash as reported; with no record of its epic it is not shown as reported. Fails on today's guess.
- The same test: two stories whose slugs share their first 32 characters, each readied and built at different times, give flow idle_slots minutes for each story, not one merged key. Fails on today's agent_name keys.
- tests/flow_test.sh, tests/flow_sections_test.sh and tests/dash_layout_test.sh assert what they did before.

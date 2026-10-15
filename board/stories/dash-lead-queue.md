---
kind: code
status: blocked
blocked_by: [dash-state-age-and-findings]
epic: dash-tells-the-truth
depends_on: [dash-state-age-and-findings]
touches: [bin/swarm.sh:config defaults, CONFIG_KEYS, load_config (lead), bin/swarm.sh:dash_fields, bin/swarm.sh:dash_render (env block, needs-you passes, layout), docs/method.md (config table), tests/config_test.sh, tests/dash_test.sh (new block), docs/dash.md (needs you), README.md (:77 dash line, if it names needs you)]
---

# New key lead = session splits needs you into the user's steps and a lead's queue

Key: `CFG_lead=off`, values off|session, in the five config places (defaults :130-142, CONFIG_KEYS :143, a load_config arm in the goal arm's form :189-190, the method.md config table, tests/config_test.sh incl. the table-default cell check like goal's :125-126). These lines are the ones codex-time-limit edits, hence the dependency. Data: dash_fields (:2855-2865) gains a field that says whether the story body has a line starting `the lead`; fix every board-row index that reads it (title is story_by_slug[..][8]). Export DASH_LEAD in the env block (:2914-2923). waiting_on_user and next stay as they are (epic out of scope). Split, only with lead = session (:3109-3153): needs you keeps `run <kind> story` rows whose story has a the lead line, auth rows, `answer` (WAITING) rows, draft HLDs, and any verbatim line; everything else (every merge row, a lead story with no the lead line, empty pane, gone/unknown, stalled) goes in a second box titled `lead's queue`, drawn right after needs you in both layouts and left out when empty. With the key off the frame is byte-for-byte today's. Epic markers (need_slugs, look) unchanged.

**Done when:**
- tests/config_test.sh: `swarm.sh config lead` prints off by default and matches the method table's Default cell, reads `session`, refuses `lead = on`; the three-list check passes. tests/dash_test.sh, new block with `lead = session` and one of each: needs you holds exactly the lead story with a **You:** line, the auth agent, the WAITING agent and the draft HLD; lead's queue holds exactly the green merge, the lead story with no **You:** line, the empty pane, the gone agent and the stalled builder, at 100 and 160 columns. Without the key, every pre-existing dash_test check passes with its lines unchanged by this PR. The PR shows the split checks failing with the split removed. The epic's checks before every stage pass.

**From review (binding; overrides the scope above where they differ):**
- Depends only on dash-state-age-and-findings; rebase over codex-time-limit's config lines rather than waiting on it.
- Needs you holds only lead stories with a **You:** line, auth rows and draft HLDs. Every merge row (green, failing, running, unknown, 'no PR on its file'), WAITING (`answer`) agents, verbatim lines, lead stories with no **You:** line (escalated ones included: dash reads escalated lead stories itself or waiting_on_user emits a line kind for them, with `next` unchanged), empty, gone or unknown panes and stalled agents go in the lead's queue.
- #144 (merged 2026-10-15) deleted `you_step` and added `impossible_block`: impossible and failed-Fable stories are both the lead's, with no **You:** step. Merge origin/main into the branch and route every escalated story (impossible_block or not) to the lead's queue; a **You:** line only exists outside the escalated block. Put any new dash_fields field last and widen the padding from 9 to 10 everywhere.
- Done when's fixture adds an escalated lead story without **You:**, a failing merge, an unknown-state merge and a WAITING agent, and asserts each is in the lead's queue and absent from needs you, in both layouts. docs/method.md's stall_minutes row says where a stalled agent shows with lead = session.

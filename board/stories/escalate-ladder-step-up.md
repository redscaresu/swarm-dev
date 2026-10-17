---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/swarm.sh:CONFIG_KEYS block (CFG defaults, CONFIG_KEYS, load_config, show_config), bin/swarm.sh:dispatch and usage header, bin/lib/lifecycle.sh:step_up (new), handover_brief (new), bin/lib/outcomes_rows.py, bin/lib/dash_render.py, tests/fixtures/dash/golden-*.txt (regenerate if present), docs/reference.md:§ escalation ladder, tests/escalate_ladder_test.sh (new), tests/config_test.sh:CONFIG_KEYS]
easy: false
estimate_lines: 260
---

# swarm.sh step-up hands a build to the next model on the same branch (escalate_ladder, off by default)

Builds on the split: close_agent in bin/lib/lifecycle.sh, outcomes_rows.py and dash_render.py. A new key escalate_ladder, empty (off) by default, for example sonnet,opus,fable, is validated against the policy's models. A new command `swarm.sh step-up <slug> <trigger>` (findings-3, ci-red-2, stalled or no-pr) closes the builder without counting a failed attempt and starts the next rung in the same worktree and branch (sonnet runs as code-sonnet, opus as code, fable as escalate). It gives the new builder a handover brief: the story, the diff against its base, open findings, failing checks, and an instruction to list every model that worked on it in the PR body. It logs event escalate with result `ok (<trigger>: <from> -> <to>)`. The escalate event already means a Fable build started (`ok (attempt N)`, bin/swarm.sh:2487), and outcomes pairs escalate events with escalate-role builds (:1187-1215). So outcomes' pairing and dash's escalation count (:5418-5428, 6005-6010) take only `ok (attempt N)` lines or steps whose target is fable. escalate-ladder-triggers calls step-up.

**Done when:**
- tests/escalate_ladder_test.sh: step-up on a sonnet build starts the opus rung in the same worktree and branch (herdr stub), with a handover brief that holds the diff and findings and names the PR-body models line, and logs one escalate line naming the trigger and both models; at the top rung, or with escalate_ladder empty, it refuses.
- The same test: on a fixture with sonnet->opus->fable step-ups, outcomes' escalate column for the Fable build has the opus->fable time, and dash counts one escalation.
- tests/config_test.sh accepts the key and rejects an unknown model.

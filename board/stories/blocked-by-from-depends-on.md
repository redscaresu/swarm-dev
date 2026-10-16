---
kind: code
status: ready
epic: leaner-faster-swarm
depends_on: []
touches: [bin/swarm.sh:unblock, waiting_on_user, SET_FM_KEYS, key_clash, templates/docs/Board.base, board/Board.base, scripts/demo-dash.sh, docs/method.md:§ Building merging paragraph, tests/config_test.sh:blocked_by checks, tests/review_test.sh:reconcile blocked_by cases, tests/dash_test.sh:blocked_by checks, tests/events_test.sh:blocked_by checks, tests/next_test.sh:blocked_by check]
---

# Nothing writes `blocked_by`: unblock and the waiting list read `depends_on`

unblock (bin/swarm.sh:2891-2911) readies a blocked story once every depends_on slug is finished, and reads depends_on only. A legacy blocked_by line is still deleted when the story flips. waiting_on_user (:2865-2884) prints `blocked: <slug> (by <its open depends_on slugs>)`, the same line shape that dash and status count. SET_FM_KEYS (:2997) drops blocked_by, and key_clash checks depends_on alone; update their comments. In templates/docs/Board.base and board/Board.base, show depends_on instead of blocked_by. scripts/demo-dash.sh writes depends_on only (:70-71) and its unblock step drops no blocked_by line (:101). docs/method.md: only the **Merging.** paragraph's key list and unblock sentence (:670-676, :680-681). Leave the header's unblock line to stacked-start-and-merge-order, and commands/plan-epic.md to plan-epic-rules. Every blocked_by in ../infrafactory/docs/stories is a subset of its story's depends_on; quote that check in the PR. bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- A test: a blocked story with depends_on [a] and no blocked_by line becomes ready on `swarm.sh unblock` once a's file is gone, and stays blocked while a is open.
- A blocked story whose blocked_by lists only part of its depends_on stays blocked while the unlisted one is open.
- `swarm.sh status --all` shows `blocked: <slug> (by a)` for a story with no blocked_by line.
- `grep -n blocked_by bin/swarm.sh` shows only unblock's legacy-line removal and its comment, and `grep -n blocked_by scripts/demo-dash.sh templates/docs/Board.base board/Board.base` prints nothing.
- The PR quotes the infrafactory subset check.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.

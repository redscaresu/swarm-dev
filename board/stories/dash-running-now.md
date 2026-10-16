---
kind: code
status: ready
epic: leaner-faster-swarm
depends_on: []
touches: [bin/swarm.sh:dash_render, dash_slow, docs/dash.md:running now bullet, epics bullet one-off rows, tests/dash_test.sh:running-now cases, one-off cases]
---

# dash has a 'running now' panel, and a one-off builder shows its PR and what it waits on instead of a bare idle

Add a 'running now' box to dash_render (bin/swarm.sh:4305-4982), with one row per open agent of this project. Each row gives the agent's name, how long it has run (from its start in agents.tsv) and its last activity: the age and tool name of the newest entry in its session .jsonl, cached in dash_slow when reading it every frame is too slow. A builder's row also gives its PR number and CI state, from the cached pr_state. After the agents, list each held story (held_for: set) with its cause. Leave the box out when nothing is open or held. Add it to the box assembly in both the wide and the narrow layout. In the 'no epic' group, a one-off builder's row never reads a bare idle. It shows its PR and what it waits on: `waits for review` while its PR is open and its story is not in review, `waits for the lead's merge` when its story is status: review, `IMPOSSIBLE` when its last reply starts IMPOSSIBLE:, and `no PR yet` otherwise. Leave dash_fields, the speedometer, the needs-you box, the board-drift line and recent to dash-speedometer-and-queue, and dash, dash_size, dash_watch and dash_reexec to dash-both-projects. docs/dash.md: a new **Running now** bullet right after the **Lead's queue** bullet (:36-40), and the one-off rows in the **Epics** bullet (:41-69). bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- tests/dash_test.sh: with two builders open (a stub herdr, fixture session logs and PR state) and one held story, the running-now box lists both builders with running time, last activity and `#<PR> <CI state>`, and the held story with its cause.
- With no agent open and nothing held, the frame has no running-now box.
- Three idle one-off builders show `#<PR> waits for review`, `waits for the lead's merge` and `IMPOSSIBLE` respectively, and no agent row in the frame reads a bare `idle`.
- Every existing dash_test check passes, in both the wide and the narrow layout.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.

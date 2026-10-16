---
kind: code
status: blocked
blocked_by: [dash-running-now, log-finding-reasons-and-reviewers]
epic: leaner-faster-swarm
depends_on: [dash-running-now, log-finding-reasons-and-reviewers]
touches: [bin/swarm.sh:dash_fields, dash_render, dash_slow, docs/dash.md:header, needs you, lead's queue and recent bullets, tests/dash_test.sh:speedometer cases, needs-you cases, board-line check, recent cases]
---

# dash's top line is a speedometer of real merges with two warning lights, and its needs-you, lead queue, board line and recent list say only what is useful

Waits on dash-running-now (dash_render's box assembly and dash_slow) and on log-finding-reasons-and-reviewers (FINDING_REVIEWERS has escaped, so finding_rows keeps escaped rows). The speedometer is the top line. It shows stories merged per day, 7-day rolling: the distinct stories whose PR merged in the last 7 days by its merged_at, read by column name from `swarm.sh outcomes --since <7 days ago>` and cached in dash_slow, divided by 7. A story file deleted by a drop or a rescope has no merged PR and never counts, and a merge counts on its merge date, not on the date the board was cleaned. It also shows two warning lights, each lit when its count is above 0. The first counts the items waiting on the lead or the user (the needs-you and lead-queue rows), with the oldest one's age: from its newest events.tsv line (review, close:*, escalated), else from its story file's last commit. The second counts escaped findings (reviewer escaped in findings.tsv) in the last 7 days. dash_fields (bin/swarm.sh:4286-4303) returns a story's first **You:** line text, not just a flag. Needs you lists only your next **You:** step, which is the first ready lead story's first **You:** line, with `+N more` when other lead stories have one. PRs awaiting your merge stay listed. A ready lead story's row (in needs-you, or in the lead's queue with lead = session) ends `waits for: you` with its **You:** text, or `waits for: the lead` when it has none. The board-drift collector passes the changed files instead of a count, and the line names them, cut to width: `board: 2 uncommitted edits in the main checkout: stories/a.md, stories/b.md`. In recent, consecutive events with the same action and target collapse into one row with ×N. A findings row cut to width keeps its `(#PR)`: cut the text, not the suffix. docs/dash.md: the **Header**, **Needs you**, **Lead's queue** and **Recent** bullets (:21-40, :70-77). bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- tests/dash_test.sh: with outcomes rows (gh stub mergedAt) for 14 distinct stories merged in the last 7 days, the top line shows 2.0 merged per day. A story whose file was dropped with no merged PR, and one merged 8 days ago whose file was deleted yesterday, do not change it.
- With a held story whose close:paused event is 3h old and a review story, the first light shows 2 items and an age of 3h. With one escaped finding 2 days old the second light shows 1, and with none it is unlit.
- With two lead stories that each have a **You:** line, needs-you shows only the first one's **You:** text and `+1 more`. A ready lead story with no **You:** line shows `waits for: the lead`.
- With two edited story files in the main checkout, the board line names both; the old exact-string check is updated.
- Three identical consecutive events show as one recent row with ×3, and a findings row longer than its column still ends with `(#<PR>)`.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.

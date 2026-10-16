---
kind: code
status: blocked
blocked_by: [drop-epic-prs]
epic: leaner-faster-swarm
depends_on: [drop-epic-prs]
touches: [bin/swarm.sh:outcomes_report, usage header: outcomes line, docs/method.md:§ Building outcomes paragraph, tests/outcomes_test.sh:timing cases]
---

# `swarm.sh outcomes` gives each build's start → PR and PR → merge times and its count of main-merge commits

Waits on drop-epic-prs (outcomes_report without its pr_per branch). In outcomes_report (bin/swarm.sh:1074-1302), the gh pr list call also asks for createdAt and commits. Columns are only ever appended, so four new ones go after findings_declined_by: pr_created_at (UTC); start_to_pr_min (pr_created_at minus started); pr_to_merge_min (merged_at minus pr_created_at); and main_merges, the commits on the PR whose headline merges the base branch into it (`Merge origin/main into story/x`, `Merge branch 'main' into …`, `Merge remote-tracking branch 'origin/main' …`). Each is empty when its inputs are. Replace the comment 'decisions reads them by name' with why columns are only appended. The header's outcomes line (:13). docs/method.md: only the `swarm.sh outcomes` paragraph (:454-478), its column list and its 'so `decisions`, which reads them by name, keeps working' (:469). In tests/outcomes_test.sh, the gh stub returns createdAt and commits. bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- tests/outcomes_test.sh: the header ends `findings_declined_by<TAB>pr_created_at<TAB>start_to_pr_min<TAB>pr_to_merge_min<TAB>main_merges`, and every earlier column keeps its place.
- For a fixture build started at 10:00Z whose PR was created at 10:40Z and merged at 12:00Z, the row has 40 and 80. With no PR, the four new fields are empty.
- A PR with two base-merge commits and one other merge commit gives main_merges 2.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.

---
kind: code
status: blocked
epic: fixes-027
depends_on: [plan-head-planned]
needs: [plan-head-planned: shares bin/lib/board.sh:plan_head, whose regex line (:1065) this story marks]
touches: [tests/loose_match_test.sh:loose_match, bin/swarm.sh:load_config, bin/lib/board.sh:stage_of, bin/lib/board.sh:epic_links, bin/lib/board.sh:plan_head, bin/lib/merge.sh:unticketed_why, bin/lib/agents.sh:story_env, bin/lib/agents.sh:settle, hooks/merge-guard.sh:command and verdict regexes (:26, :33)]
estimate_lines: 120
easy: false
risk: high
---

# The loose-match test catches a =~ whose regex holds a variable

Shares bin/lib/board.sh:plan_head with plan-head-planned (board.sh:1065). tests/loose_match_test.sh checks grep, [[ == <glob> ]] and awk ~, but not `[[ ... =~ <regex> ]]`. Flag a =~ whose right side holds a variable unless the line carries `# loose-match: ok <reason>`. Give each of the ten sites that holds one today a fix or a marker: bin/swarm.sh:278, bin/lib/board.sh:725, 1044, 1065, bin/lib/merge.sh:168, bin/lib/agents.sh:261, 1317, 1324, hooks/merge-guard.sh:26, 33. Name each and what it got in the PR. The PR touches hooks/merge-guard.sh, a safety path, so it waits for the user's merge.

**Done when:**
- In the test's fixtures, `[[ $x =~ ^${slug}- ]]` and `[[ $x =~ ${re} ]]` are flagged, and a marked line is not. The flagged cases fail if the new check is removed.
- tests/loose_match_test.sh passes over bin/ and hooks/, and tests/merge_guard_test.sh passes unchanged.

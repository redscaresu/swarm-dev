---
kind: code
status: blocked
epic: retro-gate
depends_on: [retro-recurring-list, conductor-pane-closes]
needs: [retro-recurring-list (the retro's recurring list of kinds with no check; which the collect arm; AGENTS.md and the outer-loop doc point to), conductor-pane-closes (its edit to commands/swarm.md's collect step; PR #833; lands first (a shared part))]
touches: [commands/swarm.md:collect arm, AGENTS.md:log-finding item (Useful while it runs; :87), tests/removed_test.sh:collect pins (:66-75) and header comment (:9-10), docs/reference-logs.md:The outer loop (the filing sentences)]
estimate_lines: 55
easy: true
---

# collect relays the conductor's report and closes it, and files no checks: stories: the retro's recurring list does that

Needs from retro-recurring-list: the retro's recurring list (kinds fixed on 3+ PRs since the tag, folded, with no check). The collect arm, AGENTS.md and the outer-loop doc name it in place of what they lose. Needs from conductor-pane-closes: its collect-step edit (#833) on the base first; keep what it adds. In commands/swarm.md's collect arm (:478-499), remove the checks:-filing paragraph (:478-493, from 'then run swarm.sh outcomes --since' to the .swarm/checks-filed.tsv skip). Also remove the 'A kind whose check has merged still recurs' paragraph (:494-497), which reads the same outcomes run. Keep the rest: read .swarm/conduct-<epic>.report.md, relay what merged, what is left and what waits on the user, then swarm.sh close <agent>. Add one sentence: recurring kinds with no check now belong to the retro (swarm.sh retro's recurring list, before a minor release). board.sh:472 still emits collect; no code changes. In AGENTS.md:87, the log-finding item, replace 'and /swarm-dev:swarm files a checks: story for each' with the retro's recurring list. In tests/removed_test.sh, rewrite the collect pins (:66-75) and the header comment (:9-10). The test must check that the arm names the report, the relay and swarm.sh close <agent>, and that neither commands/swarm.md nor AGENTS.md holds 'checks: <kind>' story filing, 'board/check-<kind>' or '.swarm/checks-filed.tsv'. In docs/reference-logs.md § The outer loop (:896-903), replace the sentences that say /swarm-dev:swarm files a checks: story per recurring kind, in board PR check-<kind>, notes it in .swarm/checks-filed.tsv, and tells you when a check's kind recurs. The new text: swarm.sh retro lists each recurring kind with no check before a minor release, and you and the lead decide each. Keep the text on outcomes' recurring block (:282-292), the checks: field (templates/docs/stories/README.md:76) and reference-lead.md:81's check-<kind>, which stay true. Humanizer over the changed prose; one sentence per line.

**Done when:**
- tests/removed_test.sh passes. The collect arm names the report, the relay and swarm.sh close <agent>. commands/swarm.md and AGENTS.md hold no 'board/check-<kind>' and no '.swarm/checks-filed.tsv', and AGENTS.md's log-finding item names swarm.sh retro's recurring list.
- removed_test fails on a worktree copy with the filing paragraph put back, again with AGENTS.md:87's old clause put back, and again with the close sentence removed. The PR body has the FAIL lines.
- tests/lead_stop_test.sh's collect cases and tests/doc_check_test.sh pass under scripts/select-tests.sh --run. grep -rn checks-filed AGENTS.md commands docs prints nothing, and the PR says the humanizer ran.

---
kind: code
status: ready
epic: shared-helpers
depends_on: []
touches: [bin/swarm.sh:cut_record (new), bin/lib/lifecycle.sh:close_panes, bin/lib/lifecycle.sh:close_epic, bin/lib/lifecycle.sh:cut_live, bin/lib/lifecycle.sh:own_pane, bin/lib/lifecycle.sh:live_agents, tests/name_cut_test.sh (new)]
estimate_lines: 140
easy: false
risk: high
---

# One helper for herdr's 32-character name cut, matching only exact records

herdr lists an agent by agent_name, cut to AGENT_NAME_MAX = 32 (bin/swarm.sh:442-449). The refusal for a live agent under the cut already exists (close_panes, PR #479); four close-path sites each handle the cut themselves: close_panes (bin/lib/lifecycle.sh:1508-1516, cut_live :1544), own_pane's short-name lookup (:1573), close_epic's 32-character conductor name (:1538) and live_agents' 32-character name mapped to a story (:1730-1734). Add cut_record <herdr-name> beside agent_name: the one full name (a story slug, review-<slug>, conduct-<epic>) this project's records hold under that herdr name (.swarm/state tab records, .swarm/briefs, the board's stories); it fails when none or more than one does. Each site uses it; an unrecorded long name still refuses with today's message while herdr lists a live agent under its cut. review-loop's close-spares-caller and conductor-hands-off's exact-name-metrics follow this story (epic Constraints): keep cut_record's name and output stable.

**Done when:**
- tests/close_exact_tab_test.sh and tests/close_test.sh pass unchanged.
- tests/name_cut_test.sh (new), two slugs sharing their first 32 characters: closing one never closes the other's pane; live_agents names a story only from an exact record and says its story could not be found when two match; closing an unrecorded long name refuses while herdr lists a live agent under the cut. Each check fails with cut_record swapped for a prefix match.

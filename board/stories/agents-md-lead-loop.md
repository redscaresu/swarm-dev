---
kind: lead
status: blocked
blocked_by: [tell-conductor-note, merge-command]
epic: lead-loop
depends_on: [tell-conductor-note, merge-command]
touches: [AGENTS.md (:45 tell line; :93-94 bump rule)]
---

# AGENTS.md says the plugin.json bump goes in the epic's release story and lists tell's note kind and swarm.sh merge

AGENTS.md is a shared file, so only the lead edits it (docs/method.md:258). Its bump rule (AGENTS.md:93-94: bump in any PR that changes what a user installs) is what codex reads and flags on every story PR, and what makes builders bump in story PRs. The lead, in one PR: the bump goes in the epic's release story, and a story PR without one is not a finding; the tell line (:45) lists note for a busy conductor; 'Useful while it runs' names `swarm.sh merge <pr-url>`. No the lead step: the user approved the epic.

**Done when:**
- AGENTS.md's bump paragraph names the epic's release story and says a story PR without a bump is not a finding.
- AGENTS.md's tell line lists note, and it names `swarm.sh merge`.
- The PR merged green, and humanizer ran over the changed prose.

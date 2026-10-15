---
kind: code
status: blocked
blocked_by: [codex-time-limit]
epic: lead-loop
depends_on: [codex-time-limit]
touches: [bin/swarm.sh:codex_skip_rule (version-bump sentence), commands/swarm.md (story arm, :74), tests/epic_test.sh (brief checks)]
---

# Every brief that runs a codex review says the plugin.json bump belongs to the epic's release story, so a PR without one is not a finding

codex gets no prompt (`--base` takes none, codex-time-limit.md:12), so the line is for whoever reads codex's and /code-review's output. One fixed sentence, defined once beside codex_skip_rule (added by codex-time-limit) and carried everywhere it is: review_rule (bin/swarm.sh:1468), both story_brief arms (:1670, :1683), conduct_epic_mode's whole-epic review (:2015). The same sentence in commands/swarm.md's story arm beside the review line (:74). Wording: 'The plugin.json version bump belongs to the epic's release story: a PR without one is not a finding; decline it.' No method.md change.

**Done when:**
- tests/epic_test.sh: the story-mode and epic-mode builder briefs, the story-mode conductor brief and the epic-mode conductor brief each contain `belongs to the epic's release story`.
- `grep -c "belongs to the epic's release story" bin/swarm.sh` is 1 (defined once), and commands/swarm.md contains it.
- The PR shows the check failing with the sentence dropped from one site; humanizer ran over the changed commands prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Print the line only when the story has an epic and the project has .claude-plugin/plugin.json; conductor briefs need only the plugin.json test. Wording: 'Do not bump plugin.json: the epic's release story does. A PR without the bump is not a finding; decline it.'
- Not in commands/swarm.md's one-off story arm (a one-off has no release story). The board-PR codex loops in commands/plan-epic.md:87, plan-hld.md:53 and hld.md:48 say a board-only PR needs no version bump.
- Extra Done when: a one-off story's brief and a project with no plugin.json carry no such line; the count check counts definitions, not uses.

---
kind: code
status: blocked
blocked_by: [finding-reviewer-column, codex-time-limit, codex-bump-not-a-finding]
epic: review-yield
depends_on: [finding-reviewer-column, codex-time-limit, codex-bump-not-a-finding]
touches: [bin/swarm.sh:finding_rule, commands/swarm.md (story arm, log-finding lines :75-76), docs/method.md (§ Learning across epics, :425-427), tests/epic_test.sh (conductor brief checks)]
---

# The conductor rules and commands/swarm.md tell whoever logs a finding to name the reviewer that raised it

finding_rule (bin/swarm.sh:1525-1536), which review_rule (:1519) and conduct_epic_mode (:2065) both embed, prints both log-finding lines with `--reviewer <who>` and one sentence: codex for a finding from `swarm.sh codex-review`, code-review for /code-review's, conductor for one from your own reading of the diff, lead for one the lead sent. The same in commands/swarm.md's story arm (:75-76) and method.md § Learning across epics (:425-427). Depends on codex-time-limit (the codex-review wording; review_rule, story_brief, conduct_epic_mode, commands/swarm.md:74) and codex-bump-not-a-finding (commands/swarm.md story arm and tests/epic_test.sh brief checks), as the epic's constraint says. merge-agent-ready also edits the story arm's merge sentences, not these lines: rebase only.

**Done when:**
- tests/epic_test.sh: the story-mode conductor brief (review_rule) and the epic-mode conductor brief each contain both log-finding lines with `--reviewer <who>` and the sentence mapping codex-review, /code-review, the conductor and the lead to codex, code-review, conductor and lead.
- tests/epic_test.sh: every line of commands/swarm.md that contains `log-finding` also contains `--reviewer`, and the mapping sentence is defined once (a grep count of it in bin/swarm.sh is 1), so both briefs get it from finding_rule.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs/commands prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- The mapping names a value for every source: codex, code-review, ci for the review bot and `swarm.sh findings` notes, conductor for its own reading. commands/swarm.md's arm (run by the lead) gets its own mapping: codex, code-review, ci, or lead for the lead's own reading; a done_when greps that mapping there.
- Done when pulls both log-finding lines out of the rendered conductor brief, fills the placeholders (--reviewer codex, a kind, a URL, text), runs them against a temp project, and checks field 6 is codex with field 5 fixed or declined.
- The codex-bump-not-a-finding dependency is through tests/epic_test.sh's brief checks and the epic constraint. Shared file-level touches with other epics are rebases. method.md's log-finding lines belong to finding-reviewer-column; this story only checks they name --reviewer.

---
kind: code
status: blocked
epic: review-loop
depends_on: [next-review-round, owner-waits-green]
needs: [next-review-round: `review-agent --next` and its round count (bin/lib/build.sh:review_agent, review_round), owner-waits-green: the wait-pr and triage step in bin/lib/build.sh:review_brief]
touches: [bin/lib/build.sh:review_brief, AGENTS.md:Using swarm-dev in a project, docs/reference.md:Building review paragraph, tests/review_agent_test.sh:findings round cases]
estimate_lines: 160
easy: false
risk: high
---

# The review agent triages its findings, tells the builder and runs the next round

Uses next-review-round's `review-agent --next` (bin/lib/build.sh:review_agent) and owner-waits-green's wait-pr and triage step in bin/lib/build.sh:review_brief. Add to review_brief: after each review, fix or decline each finding, logged with log-finding --round <n> (reuse finding_rule, build.sh:110-138), and write the findings file with its head: line as now. With findings to fix: `swarm.sh wait <slug>`, then `swarm.sh tell <slug> findings <file>`. tell dies on a busy builder (agents.sh:1634-1640). When tell says the build was stepped up, wait on the new builder; when it says the story is held, stop. Then wait for the builder, run the green step on the new head, run --next and the round it prints (codex alone from round 2). A round with nothing fixed is a pass. Until owner-merge-handoff lands, a pass ends as today. The brief keeps 'never edit, commit or push'. AGENTS.md's review-agent line (AGENTS.md:75) changes here and nowhere else in this epic. Word it so it stays true once the agent merges. less-noise's AGENTS.md stories merge after this one.

**Done when:**
- A test runs the brief's tell and --next commands as the brief writes them, from a stand-in review pane in the story's worktree, against a fixture project.
- With the builder busy, that tell refuses ('still working'). Once the builder is idle, it is logged tell:findings ok and the builder's stub receives the file.
- The brief's --next then prints round 2 with codex alone.
- tests/review_agent_test.sh pins the fix-or-decline, log-finding --round, wait-before-tell and pass lines, and the absence of the conductor-triage text; tests/doc_check_test.sh passes.

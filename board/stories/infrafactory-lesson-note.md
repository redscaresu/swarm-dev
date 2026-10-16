---
kind: lead
status: ready
epic: leaner-faster-swarm
depends_on: []
touches: [infrafactory: AGENTS.md:Lessons]
---

# infrafactory's six tagged review rules become one 'decline these in review' note

No new rules (decided 2026-10-14). The lead edits the Lessons section of ../infrafactory/AGENTS.md (:146-152). It keeps the vacuous-test line, which findings-checks-fail-lines makes `swarm.sh findings` check. It replaces the other six (state-duplication, docs-misstate-code, denylist, fails-open, regression-from-fix, unbounded-call) with one note for reviewers: in review, decline a PR that breaks any of them, each named in a few words. The note keeps all six `<!-- lesson: <kind> -->` tags on its one line, so `swarm.sh lessons` still reads those kinds as ruled and proposes none of them again. The lead opens the PR in infrafactory. Agents never edit infrafactory's AGENTS.md,. The lead merges it (the user allowed the lead to merge infrafactory PRs, 2026-10-16). **You:** none.

**Done when:**
- On infrafactory's main, AGENTS.md's Lessons section has two lines carrying seven `lesson:` tags between them.
- `swarm.sh lessons --all` in infrafactory lists none of the seven kinds as a candidate.
- The merged PR is linked on this story.

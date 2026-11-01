---
kind: code
status: ready
epic: machine-usable
depends_on: []
touches: [bin/lib/build.sh:mutation_rule, AGENTS.md:Prove a mutation paragraph, tests/fail_lines_test.sh:mutation_rule check]
estimate_lines: 35
easy: true
---

# Mutation proofs run on a worktree copy once the PR is open

#695: in-place proofs after the PR opens left uncommitted changes that made review-agent refuse. Change mutation_rule (bin/lib/build.sh:367-369): before the PR opens, break the fix in place with cp as today; after it opens, prove on a copy of the worktree without .git, never in place. Change AGENTS.md's 'Prove a mutation without git' paragraph (AGENTS.md:184-189) the same way, in this PR (it is the user's doc: say so in the PR). rules.md rule 11 stays as it is (epic constraint). The epic's Done when 3 also puts 'push what is ready, and put further points in the PR body' in mutation_rule and AGENTS.md, in this PR (HLD:452-456).

**Done when:**
- mutation_rule's text says: before the PR opens, in place with cp; after it opens, on a copy of the worktree without .git, never in place.
- tests/fail_lines_test.sh:263-265 still finds "paste each test's FAIL line" and "into the PR body", and a new check there finds the after-the-PR-opens sentence; the new check goes red with that sentence removed.
- mutation_rule and AGENTS.md's mutation paragraph also say to push what is ready and put further points in the PR body; a check finds it, and goes red with it removed.
- AGENTS.md's mutation paragraph states the same before/after split; the PR says AGENTS.md changed.

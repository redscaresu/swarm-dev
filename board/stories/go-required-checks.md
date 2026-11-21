---
kind: lead
status: blocked
depends_on: [go-checks-ci, go-macos-job]
needs: go-checks-ci (the go-checks job and its green runs on a PR, a board-only PR and main's push); go-macos-job (the macos-tests job and the same green runs)
touches: [ruleset 24181590:required_status_checks, AGENTS.md:required checks sentence (CI ... is required on main)]
estimate_lines: 0
easy: true
risk: high
---

# You: add go-checks and macos-tests to main's required checks once both have run green

Uses the go-checks job from go-checks-ci and the macos-tests job from go-macos-job. Marked risk: high because it changes the checks that gate every merge to main. Ready once both CI PRs are merged (go-held-merges).
- Lead, before your step: check that each job has a green run on main's push after its merge, and on a board-only PR (steps skipped, job green). Check that the check-run names are exactly go-checks and macos-tests. A required check that never reports on a board-only or version-only PR blocks that PR, and wait-pr exits 2 on it.
- **You:** add go-checks and macos-tests to ruleset 24181590's required status checks, bound to GitHub Actions (HLD:505-506).
- Lead, right after: on this story's branch, add a sentence after AGENTS.md:279's saying go-checks and macos-tests are required on main too. Write a new sentence, not a longer list. Merge it through `swarm.sh merge`. go-module-build, the only other story here that edits AGENTS.md, has merged by then: this story waits on it through go-checks-ci (codex, critic).
- Lead, after: confirm that the next board-only PR and the next code PR each merge with both checks reported.

**Done when:**
- `gh api repos/redscaresu/swarm-dev/rulesets/24181590` lists go-checks and macos-tests among the required checks. AGENTS.md on main says both are required, in a sentence of its own, merged after the ruleset change. The first board-only PR and the first code PR after the change each merged with both checks green.

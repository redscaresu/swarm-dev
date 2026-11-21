---
kind: lead
status: blocked
epic: release-ci
depends_on: [build-check, go-required-checks]
needs: build-check (the build-check job, and its runs on a story PR, a board-only PR and the tmp/ bump PR); go-required-checks (its change to ruleset 24181590 and its AGENTS.md sentence, which this story's change and sentence follow)
touches: [ruleset 24181590:required_status_checks, AGENTS.md:required checks sentence (CI ... is required on main)]
estimate_lines: 2
easy: true
risk: high
---

# You: add build-check to main's required checks once it has reported on a story PR and on a bump

Uses build-check's job and runs, and comes after go-required-checks, which changes the same ruleset and the same AGENTS.md line (AGENTS.md:308). go-required-checks' own needs (go-checks-ci, go-macos-job) have merged, so it waits only on your step there.
- Lead, before: check that the check-run name is exactly `build-check`; that it was green with its build steps skipped on a story PR and on a board-only PR; and that it built on build-check's tmp/ bump PR. It has no push trigger, so main's push has no build-check run to check (codex, critic). No bump can merge here before v0.32.0 (see contradictions).
- **You:** add build-check to ruleset 24181590's required status checks, bound to GitHub Actions. Keep every context already there: a PUT replaces the whole rules array.
- Lead, right after: on this story's branch, add one sentence after AGENTS.md:308-310's CI lines saying build-check is required on main, builds the four binaries on a PR that changes plugin.json, and skips its steps on every other PR. Write a new sentence, not a longer list. Merge it through `swarm.sh merge`. This is the only story in the epic that edits AGENTS.md.
- Lead, after: the next board-only PR and the next code PR each merge with build-check reported.

**Done when:**
- `gh api repos/redscaresu/swarm-dev/rulesets/24181590` lists build-check among the required checks, and every context it listed before is still there. AGENTS.md on main says build-check is required, in a sentence of its own. The first board-only PR and the first code PR after the change each merged with build-check green.

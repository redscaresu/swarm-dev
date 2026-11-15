---
kind: docs
status: ready
depends_on: []
touches: [README.md, AGENTS.md, docs/method.md, docs/running.md, docs/reference-building.md, docs/reference-lead.md, docs/reference-logs.md, docs/reference-merging.md, docs/reference-models.md, docs/reference-planning.md, commands/swarm.md, skills/swarm-dev/SKILL.md]
estimate_lines: 200
easy: false
---

# Bring README, AGENTS.md and the docs in line with everything merged since v0.30.0, for the v0.30.1 release

The user asked for an early release, v0.30.1, cut from main before the rest of v0.31.0 is done (2026-11-15). The release rules (AGENTS.md, the release arm in commands/swarm.md) say that before the version bump, README.md, AGENTS.md, docs/ and commands/ must cover every behaviour change since the last tag. About 126 PRs have merged since v0.30.0. Each story was meant to update its own docs, but nobody has checked them as a whole.

Audit, then fix:
1. List the behaviour changes since v0.30.0: `git log --format='%h %s' v0.30.0..origin/main`. Group them by what a user runs, sees or must do (new commands and flags, new config keys, changed defaults, new lines in `wait --lead` / `status` / `next`, changed merge holds, new board fields).
2. For each one, check that README.md, AGENTS.md, docs/ (method.md's settings table, running.md, the reference-*.md files) and commands/*.md say it, and say it correctly. Note each gap or wrong line, with the PR it came from.
3. Fix each gap and wrong line in place. Keep each doc's own structure. Do not restate what a doc already says correctly.
4. Specific items to check, because they changed provider and merge behaviour this weekend:
   - Bedrock: agents get `AWS_BEARER_TOKEN_BEDROCK` and the `ANTHROPIC_DEFAULT_*_MODEL` pins when `CLAUDE_CODE_USE_BEDROCK` is on (#919), beside Foundry; a Claude subscription needs nothing passed. README, AGENTS.md and docs/reference-building.md should state all three providers.
   - The dropped-lines check: both-sides lines (#918) and lines from an already-merged parent (#941) no longer count.
   - A model error skips the resumes and names a fresh restart (#921). Fallback reviewer on a codex timeout or connection failure, if #899 has merged by the time you build.
   - `swarm.sh retro`, its sections, and the retro file format (retro-report's PRs).
   - `swarm.sh handover` (#939) and `usage_warn_percent`, if usage-warning has merged.
5. Run the humanizer skill over the prose you change (AGENTS.md: "Before the PR opens, run the humanizer skill"). Say in the PR that you did.
6. The PR body lists each behaviour change and the doc that now covers it, as a table, so the release PR can link it.

Do not bump the version in .claude-plugin/plugin.json: the release PR does that.

**Done when:**
- The PR body has a table with one row per behaviour change since v0.30.0 that a user runs, sees or must do, and the doc and section that covers it
- README.md and AGENTS.md name all three providers (Claude subscription, Azure Foundry, AWS Bedrock) and what each needs
- tests/doc_check_test.sh passes, so every command the docs name exists in swarm.sh
- scripts/select-tests.sh --run passes
- The PR says the humanizer pass ran over the changed prose

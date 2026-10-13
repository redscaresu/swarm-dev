---
kind: code
status: ready
touches: [bin/swarm.sh (new outcomes function, its dispatch arm and usage line), tests/outcomes_test.sh (new), docs/method.md (§ The audit log, one paragraph), README.md (command list)]
---

# `swarm.sh outcomes`: one row per build, joining what the logs already hold

The logs already record every agent since 2026-09-29 (`.swarm/agents.tsv`: role, model, effort,
session id), every command (`events.tsv`: tell, close, review per slug), every fixed review finding
(`findings.tsv`, by PR) and each session's tokens (`swarm.sh cost`, from the session's .jsonl). Nothing
joins them per story, so "which model and effort built which kind of story, at what cost, and how did
it go" cannot be answered. Add a read-only `swarm.sh outcomes [--since YYYY-MM-DD]` that prints TSV,
one row per builder agent (roles code, code-risky, docs, chore, verify, escalate):

`date, slug, kind, risk, role, model, effort, cost_usd, tokens, tells, closes, findings_fixed, pr, pr_state, attempts`

- **slug**: the agents.tsv name is cut at 32 characters, so take the full slug from the session's
  .jsonl `cwd` (the worktree path ends in the slug), falling back to the agents.tsv name.
- **kind, risk**: from the story file, or from git history (`git log --diff-filter=D -1 -- <board>/stories/<slug>.md`, then `git show <commit>^:<path>`) when the story merged and was deleted. Empty when neither has it.
- **cost_usd, tokens**: the same per-session sums and prices `cost_report` uses; reuse its code, do not copy it.
- **tells, closes**: events.tsv lines with that slug as target.
- **pr, pr_state**: `gh pr list --head story/<slug> --state all` in the story's repo (repo_dir of the story's `repo:`); a gh failure leaves both empty, never fails the run.
- **findings_fixed**: findings.tsv lines for that PR.
- **attempts**: the number of builder rows for the slug up to and including this one.

Read-only: in READ_ONLY_COMMANDS, logs nothing, writes nothing. bash 3.2, JSON via python3 as the other reports do.

**Done when:**
- A fixture with three builds (a merged code story whose file was deleted from the board, a docs story still on the board, and a story built twice) prints three rows with the right slug (one name longer than 32 characters), kind, risk, model, effort, cost, tells, findings and attempts 1, 1, 2. Shown red on the old code.
- With `gh` failing, the run still prints every row with pr and pr_state empty.
- events_test's read-only check covers `outcomes` (it logs nothing).
- Run on infrafactory's real `.swarm/`, it prints a row for every builder row in agents.tsv (119 on 2026-10-13) and none has an empty slug; the PR body shows the counts by role/model/pr_state (no story text).
- No plugin.json bump: it ships in the next release story. Method § The audit log and the README command list name the command.

**Not in scope:** any routing change, any new logging, a model that learns from the rows.

---
status: later
---

# The swarm spends its time building, not waiting on the lead: a stuck review times out, a merge does not stall the other PRs, and the conductor carries a wave through to the end

**Parked (user, 2026-10-25):** set `later` so planning the 0.28 HLD comes first. Its remaining stories are all lead stories, parked with it, each with a note saying where it goes.

**Done when:**
- Every codex call the swarm makes or tells an agent to make (`swarm.sh` briefs, conduct rules, commands/*.md) goes through one form with a time limit (default 10 minutes, a config key). A codex that runs past it is stopped, and the review counts as "codex unavailable": the lead or conductor reviews the diff and the PR says "codex skipped: timed out". A stub codex that sleeps past a short limit shows this in a test. The form never passes `--base` together with a prompt (codex refuses that).
- swarm-dev's main ruleset no longer requires a branch to be up to date before merge (`strict_required_status_checks_policy: false`); the required checks are unchanged. The repo is user-owned, so GitHub's merge queue is not available.
- swarm-dev's `.claude/swarm/config` sets `merge = agent`: the conductor merges its own green, reviewed PRs (head SHA pinned), runs `unblock`, and builds stories that became ready in the same run, instead of reporting and stopping. infrafactory keeps `merge = human`.
- After a merge, `swarm.sh reconcile` does the cleanup the lead now does by hand: closes the story's builder, removes its worktree and local and origin `story/<slug>` branches, and pulls the main checkout, keeping the board's uncommitted status edits; a story file the merge deleted is taken as deleted, not left as a conflict. It absorbs the board story `story-after-unmerged-close` (the same cleanup for a PR closed unmerged).
- `swarm.sh wait <conductor>` has a mode that keeps waiting past the hour until the conductor reports, needs a login, or is stuck on a prompt; it never nudges.
- method.md: a board-only PR (no code) gets one codex pass plus the lead's own review, not repeated passes. The lead's messages to agents go through `swarm.sh tell` (which logs them), not a bare `herdr agent prompt`.

**Out of scope:** a merge queue. The planning `codex` panes of /plan-hld and /plan-epic: they run under `wait`'s timeout and the lead closes them. `merge = agent` for infrafactory or any other project. Changing which checks are required.

**Constraints:** bash 3.2, shellcheck, every tests/*_test.sh. New config keys default to today's behaviour, pinned by the defaults test; turning anything on is a `lead` story. One exception: the codex time limit ships on (10 minutes), since today's behaviour is an unbounded hang. macOS has no `timeout`, so the limit is enforced in swarm.sh (bash or python3), not by a coreutils binary. The block-red-pr-merge hook still applies to the conductor's merges (literal PR number, `--match-head-commit`). Each code story depends on the goal-for-builders story that changes the same function (wait_agent, close_agent, clear_build, the conduct rules), not on the whole epic. Bump plugin.json in a release story.

**Your part:** none beyond the go-ahead already given on 2026-10-15. The ruleset change (done 2026-10-15: strict_required_status_checks_policy false, the five required checks unchanged) and the `merge = agent` switch are the lead's.

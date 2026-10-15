---
status: active
---

# The lead's loop is one logged command per step, a busy conductor can still be told things, and parallel epics do not collide

**Done when:**
- `swarm.sh merge <pr-url>` merges a green PR the way the lead does by hand today: it reads the head SHA, refuses unless every check on that head passed and the PR's story is in `review` (or the PR is a board-only PR the caller names with `--board`), merges with the repo's allowed method (squash when allowed), `--admin` only when the config allows it, and `--match-head-commit`; then waits, with a time limit, for CI on the merge commit on the base branch, and exits non-zero naming the run when it is red. It then runs reconcile's cleanup for the story. Every step is one events.tsv line with its time (merge, main-ci ok|red|timeout). Stub gh tests cover green, a red head, a changed head, and a red main.
- A conductor can be told things while it works: `swarm.sh tell <conductor> note <file>` appends to `.swarm/inbox/<conductor>.md` instead of refusing, logs `tell:note`, and the conductor's rules say to read and clear its inbox after each wait returns. A builder still refuses as today.
- `swarm.sh story <slug>` warns when an open build in another epic (any story in `review`, or with an open builder) lists a `touches` entry naming the same function or file (bin/swarm.sh:<fn> matched on <fn>), and names it; `--wait` refuses until it is gone. The conductor brief says to start a warned story only after the other merges.
- The review prompt every codex call carries (briefs, conduct rules, commands) says the plugin.json bump belongs to the epic's release story, so it is not a finding; a check greps for that line.
- A test fails when board/stories/README.md and templates/docs/stories/README.md differ (swarm-dev's own board), so the two cannot drift again.

**Out of scope:** an auto-merge daemon. Merging for infrafactory without the lead. Changing what reviews look for beyond the version-bump line.

**Constraints:** bash 3.2, shellcheck, every tests/*_test.sh. The block-red-pr-merge hook only inspects the outer Bash command, so it never sees the `gh pr merge` that `merge` runs: `merge`'s own check (every check on the pinned head completed and passed, at least one check present, head unchanged at merge time via `--match-head-commit`) is the only gate, and must fail closed: a gh error, an empty check list or a pending check refuses. Tests cover each. `merge` follows flow-speedups' merge-agent-ready rules (pinned SHA, main check) so the conductor and the lead share one code path: depend on it, or land first and have merge-agent-ready call it. Stories touching codex prompts depend on flow-speedups' codex-time-limit. Bump plugin.json in a release story.

**Checks before every stage:** every PR passes shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .`; shows each new check failing with its code removed; and ran humanizer over changed README/docs prose and its description, saying so.

**Your part:** none; the user approved this on 2026-10-15.

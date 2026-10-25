---
kind: code
status: ready
depends_on: []
touches: [bin/swarm.sh:load_config, bin/swarm.sh:base_for, bin/lib/build.sh:story_brief, bin/lib/build.sh:conduct_brief, bin/lib/build.sh:stack_start, bin/lib/lifecycle.sh:board_pr, tests/removed_test.sh, docs/method.md]
estimate_lines: 200
easy: false
env: [ANTHROPIC_FOUNDRY_RESOURCE, ANTHROPIC_FOUNDRY_API_KEY, ANTHROPIC_DEFAULT_FABLE_MODEL, ANTHROPIC_DEFAULT_OPUS_MODEL, ANTHROPIC_DEFAULT_SONNET_MODEL, ANTHROPIC_DEFAULT_HAIKU_MODEL]  # Foundry until agent_env ships
---

# Bring back base_branches and sign_commits; warn on removed keys

For 0.27.1, a patch release (user, 2026-10-25). Another project's board, a vault folder for repos
under ~/Work, sets `base_branches = dev main`, `sign_commits = true`, `pr_per = epic`,
`finished = mark`, `review_bot = auto` and `keep_panes = true`. #214 (53f3b82, 2026-10-16) removed
all of them, after checking only swarm-dev's and infrafactory's configs. Since then load_config dies
on each as an unknown key (bin/swarm.sh:251), so every swarm.sh command fails on that board.

- **base_branches comes back** as it was before 53f3b82 (`git show 53f3b82^:bin/swarm.sh`, base_for
  at :261): a space-separated list, and base_for takes the first branch origin has. That board's
  repos must branch from `dev` where it exists, else `main`, and their default branch is often `main`.
  Unset, base_for behaves as it does now.
- **sign_commits comes back**: `true` puts the old sign rule (53f3b82^:bin/swarm.sh:2014) in every
  builder's and conductor's brief, and swarm.sh's own commits and merges pass `-S` (53f3b82^:2723):
  board_pr's commit (bin/lib/lifecycle.sh:131) and stack_start's merge of a parent
  (bin/lib/build.sh:809) included.
- **pr_per, finished, review_bot and keep_panes are ignored with a warning** on stderr naming the key
  and that it was removed, instead of dying. Any other unknown key still dies.
- tests/removed_test.sh lists base_branches and sign_commits as gone: take them out of its patterns.
- docs/method.md's settings table lists both keys again.

**Done when:**
- A test shows base_branches = `dev main` picks `dev` on a repo that has it and `main` on one that
  does not, and fails if base_for ignores the key.
- A test shows sign_commits = true puts the sign rule in a builder's and a conductor's brief, and none
  when unset, and that board_pr's commit and stack_start's merge pass `-S` when it is on.
- A test shows each of the four removed keys warns and loads, and a made-up key still dies.
- `make test` passes.

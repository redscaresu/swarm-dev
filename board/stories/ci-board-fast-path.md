---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [.github/workflows/ci.yml:board-only gate and checkout depth in shellcheck, test, plugin-validate, scripts/board-only.sh (new), tests/board_only_test.sh (new)]
risk: high
easy: false
estimate_lines: 120
---

# A board-only PR skips the test, shellcheck and plugin-validate steps

The required contexts are the job names shellcheck, test, plugin-validate, gitleaks and zizmor (ruleset 'main'), so no workflow or job is skipped. Each of the three jobs first runs scripts/board-only.sh and gates its later steps with `if:` on that step's output. The script reads the changed paths with `git diff --name-only --no-renames <event base SHA>...HEAD`, after a checkout with enough fetch depth for the base (today it is depth 1, ci.yml:17-20,28-31), so a rename out of board/ lists its old path. A PR is board-only when every path is under board/, as merge --board defines it (bin/swarm.sh:4062-4110). Pushes to main, an empty diff and a failed diff all run everything. The shellcheck step covers scripts/board-only.sh (ci.yml:23). Actions are pinned by SHA, with persist-credentials false and read-only permissions (zizmor). risk high: a gate that reads a code PR as board-only lets untested code merge. The live run of a board-only PR is after-release-checks'.

A release PR is fast too (user, 2026-10-17: three releases in this epic must not add CI time). A PR whose diff is only board/, the `version` field of .claude-plugin/plugin.json, and release notes counts as fast-path. scripts/board-only.sh compares plugin.json as parsed JSON, so a change to any other field fails the check. It also requires that the PR's base is main's latest commit and that main's CI on that commit passed (`gh api .../commits/<sha>/check-runs`). Otherwise the full suite runs, because the code being released has to be the code that was tested.

**Done when:**
- scripts/board-only.sh fixtures: a version-only plugin.json diff with a green, current base is fast-path. A plugin.json diff that also changes `description`, a base behind main, and a base whose CI was red each run the full suite.
- tests/board_only_test.sh: on a fixture git repo, scripts/board-only.sh says board-only for a diff of board/ paths only, and not for a mixed diff, a rename out of board/, an empty diff, a failed git diff or a push event.
- The same test reads ci.yml: in shellcheck, test and plugin-validate, every step after the gate has an `if:` naming the gate step's real id and output, the checkout fetches the base, and the shellcheck step names scripts/board-only.sh.
- zizmor passes on ci.yml.

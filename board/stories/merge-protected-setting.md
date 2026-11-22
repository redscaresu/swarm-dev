---
kind: code
status: ready
depends_on: []
touches: [bin/swarm.sh:CFG_ defaults (merge_protected), bin/swarm.sh:CONFIG_KEYS, bin/swarm.sh:load_config's arms (merge_protected), bin/lib/merge.sh:the protected-path hold (around :417-440), tests/merge_protected_setting_test.sh, docs/reference-merging.md:§ Merging (the protected-path hold), docs/method.md:§ Configuring a project (settings table), docs/port/swarm-names.tsv:SWARM_ rows if any]
estimate_lines: 120
easy: false
---

# A merge_protected setting lets swarm.sh merge land a reviewed PR that changes a protected path, off by default

The user asked for it on 2026-11-22, so they can leave the swarm running overnight without every PR that touches `.github/`, `hooks/`, `.claude-plugin/`, `internal/layers/` or the guard, merge, release and agent-env packages waiting for their click. On 2026-11-21 and 22 most of the night's waits were these holds.

- Add the setting `merge_protected`, `off` (the default) or `on`, beside `merge_admin` in bin/swarm.sh's CFG_ defaults, CONFIG_KEYS and load_config. Any other value dies naming the line, as merge_admin's does.
- With `merge_protected = on`, swarm.sh merge's protected-path hold (bin/lib/merge.sh, around :417-440) does not hold a story PR. It prints `protected path: <path>, merged under merge_protected = on` and records the event, then merges as it does any reviewed story PR. With `off`, nothing changes.
- The setting lifts only the protected-path hold. The dropped-lines hold, the `costs: money` hold, the CI gate, the review gate and the guard hook's refusals all stay. A `--board` PR and `--release` keep their own routes.
- The setting ships off. Turning it on is the user's edit to .claude/swarm/config, not this PR.
- Docs move with it. docs/reference-merging.md § Merging names the setting where it describes the protected-path hold. docs/method.md's settings table gains a row at its sorted place.

**Done when:**
- A new test, tests/merge_protected_setting_test.sh, runs swarm.sh merge under the existing merge fixtures on a reviewed story PR that changes `.github/workflows/x.yml`. With the setting unset and with `off`, the merge is held with the `which only the user merges` line and gh merges nothing. With `on`, gh's merge stub is called once, and the output names the protected path and the setting.
- With `on`, a PR whose head drops a base line is still held by the dropped-lines hold, and a `costs: money` story's PR is still held.
- `merge_protected = maybe` in the config fails with a line naming the key and its line.
- The test goes red when the `on` branch is removed (proved on a copy of the worktree without .git).
- scripts/select-tests.sh --run passes

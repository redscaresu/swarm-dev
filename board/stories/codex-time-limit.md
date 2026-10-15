---
kind: code
status: blocked
blocked_by: [goal-conductor-rule]
epic: flow-speedups
depends_on: [goal-conductor-rule]
touches: [bin/swarm.sh:codex_review (new), bin/swarm.sh:codex_skip_rule (new shared sentence), bin/swarm.sh:dispatch (codex-review arm), bin/swarm.sh:usage header (codex-review line), bin/swarm.sh:config defaults, CONFIG_KEYS, load_config (codex_minutes), bin/swarm.sh:review_rule, bin/swarm.sh:story_brief (codex sentence, both modes), bin/swarm.sh:conduct_epic_mode (whole-epic review), tests/codex_test.sh (new), tests/config_test.sh, tests/epic_test.sh (builder and conductor brief checks), commands/swarm.md (story arm, :74), docs/method.md (config table; § Building, **Review before closing.**), README.md (:25, the review line), docs/method.md (:368-369 builder codex loop, :442 epic pass)]
risk: high
---

# Every codex review goes through `swarm.sh codex-review <base>`, which stops codex after codex_minutes (10) and says codex skipped: timed out

A new `codex-review <base>` arm runs `codex exec review --base origin/<base>` in the cwd, with no prompt, ever. It stops the whole process tree after codex_minutes, using kill_tree (bin/swarm.sh:3819) or python3, not coreutils `timeout`, which macOS lacks. SWARM_CODEX_SECONDS overrides the limit for tests, like SWARM_STALL_POLL_MS. On timeout it prints `codex skipped: timed out after <N> min` and exits non-zero. New key codex_minutes: default 10, validated like stall_minutes, with a CONFIG_KEYS entry and a method table row. It ships on, the one exception the epic allows. One helper sentence covers both 'usage limit' and 'timed out': a builder carries on, and the conductor or lead reviews the diff itself and writes 'codex skipped: <why>' in the PR. It replaces the four bare `codex exec review` texts (review_rule :1434, story_brief :1620 and :1633, conduct_epic_mode :1920) and commands/swarm.md:74. Briefs run it through SWARM_PROJECT=<project>, as finding_rule does, so a sibling repo's worktree still reads the config. Since the arm is logged, events.tsv records each timeout.

**Done when:**
- tests/codex_test.sh (new): with a `codex` stub on PATH that records its args and sleeps 60, and SWARM_CODEX_SECONDS=2, `swarm.sh codex-review main` exits non-zero within 10 s and prints `codex skipped: timed out`. Afterwards pgrep finds neither the stub nor its child sleep.
- A stub that prints a finding and exits 0: codex-review exits 0 and prints the finding. The stub's recorded args are exactly `exec review --base origin/main`, with no further argument.
- tests/config_test.sh: `swarm.sh config codex_minutes` prints 10 by default, and that matches the method table's Default cell. `codex_minutes = 0` and `= abc` are refused.
- tests/epic_test.sh: the story-mode and epic-mode builder briefs, the story-mode conductor brief (review_rule) and the epic-mode conductor brief's whole-epic review each contain `codex-review` and `codex skipped: timed out`. `grep -c 'codex exec review' bin/swarm.sh` is 1 (the arm itself), and commands/*.md contain none.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs/commands prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Stop codex in two steps: TERM to the whole process tree, a short grace (a few seconds), then KILL whatever is left. Run codex with stdin from /dev/null.
- Report a timeout through `die 'codex skipped: timed out after <N> min'`, so events.tsv's codex-review line carries it; a usage-limit exit stays distinguishable.
- Extra Done when: a second stub that traps TERM and sleeps on is gone within limit plus grace; events.tsv's codex-review line holds 'codex skipped: timed out'; the leftover-process check uses `pgrep -f` on a marker unique to the stub, polled for up to 2 s.
- Update every place method.md describes a codex run, including the builder-brief codex loop (docs/method.md:368-369) and the epic-mode whole-epic pass (:442), not only the config table and **Review before closing.**
- Planning `codex` panes (/plan-hld, /plan-epic) are out of scope: they run under `wait`'s timeout and the lead closes them. Say so in method.md in one line.

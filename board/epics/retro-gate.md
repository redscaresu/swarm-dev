---
status: draft
hld: 2026-10-25-swarm-dev-0-28
stage: v0.31.0
depends_on: [rules-file, ladder-cost]
---

# No release without a retro

No release without a retro: merge --release refuses a minor bump unless a done retro file covering up to the version being released is on main, and refuses a patch bump when a non-fix change is since the tag; one definition of a fix serves next and the gate; next prints `retro` with its exit before `release`; the collect arm keeps its report and close steps and loses only the checks:-filing paragraph; v0.31.0 is cut from main's bin/swarm.sh with the gate's output quoted. HLD Goal 1, Design § The retro gate (the gate, next, the window).

**Done when:**
- release_check (bin/lib/merge.sh:1249-1282) refuses a minor bump unless a retro file at RELEASE_BASE has `done:` set and `covers: <from>..<to>` with <from> at or before the last tag and <to> equal to the version being released (minor vs patch from the semver parse at merge.sh:1262); release_docs still runs; tests cover minor with the right retro, minor with a stale retro (covers ends at an earlier version: refused), minor with none, and patch.
- One function in bin/lib defines a non-fix change since the tag (the plan writes it once: a merged PR since the tag whose story was not `kind: fix` or a `fix-main-*` story, or whose title says so; the exact rule is the plan's, with a fixture test) and both next's retro arm and release_check use it; release_check refuses a patch bump when it finds a non-fix change; a test for the patch-with-feature case.
- next prints `retro v<next>: open retro-v<next> (kind: lead), then swarm.sh retro --since <tag>` before `release` (bin/lib/board.sh:281-283) when origin/<base> has a non-fix change since the tag and no done retro file covers up to <next>; hooks/lead-stop.sh is not changed (an unknown step allows the stop, hooks/lead-stop.sh:9-11; tests/lead_stop_test.sh pins the collect arm stays); tests/next_test.sh pins the retro line, its absence after the retro file lands, and the as-today case for a project with no retro dir.
- commands/swarm.md's collect arm keeps the report, relay and close steps (commands/swarm.md:160-180; board.sh:213 still emits collect; merge.sh:494 counts the close) and loses only the checks:-filing paragraph, which the retro's recurring-kinds list replaces; tests/removed_test.sh:19 is updated in the same story; commands/swarm.md's release arm names the retro step.
- The gate is recorded as the 'ship switched off' exception in docs/reference.md:328-333's terms (every plugin board with a v<version> tag gains it on upgrade, by this HLD's Goal 1) and the v0.31.0 release PR lists it as a behaviour change every project gets.
- docs/reference.md, README.md, AGENTS.md and commands/swarm.md's release arm describe the retro step and the gate; docs/features.tsv has a retro row with metric `flow: releases cut with a done retro, share` and baseline 0 of 4 stage releases; doc_check passes.
- commands/swarm.md has an arm for the `retro v<next>` step: it opens and completes the retro's lead story, after which `next` reaches `release`; the same test as stage-gating's fails if `next` prints a step with no arm.

**Out of scope:**
The retro command, the file format and the retro run (retro-report); handover and usage (handover-usage); a retro on patches; a registry of boards.

**Constraints:**
- release_check reads everything at RELEASE_BASE, in bash 3.2 (merge.sh:1246-1248): the retro file is read at that commit, not the checkout.
- The gate story names retro-report's format story in depends_on (it reads `covers:` and `done:`); the retro-v0.31.0 story in retro-report names this epic's code stories in depends_on.
- tests/removed_test.sh pins the collect text; the retro's names avoid the banned ones.
- The v0.31.0 cut runs from main's bin/swarm.sh (the installed plugin is v0.30.0 and has no gate) in the release-v0.31.0 story: its PR body quotes the gate's output and names the commit whose swarm.sh ran it.
- Touch docs/features.tsv as `docs/features.tsv:retro row`; bash 3.2, shellcheck, loose_match_test, make test; humanizer over README, docs and commands prose.

**Areas:** bin/lib/merge.sh:release_check, bin/lib/ (the non-fix definition helper), bin/lib/board.sh:next_step retro arm, commands/swarm.md:collect and release arms, docs/reference.md:release gate, docs/features.tsv:retro row, README.md, AGENTS.md:release lines, tests/ (merge release, next, lead_stop, removed)

**Your part:**
User: pick the version when next names the retro (minor, from what merged since the tag). The v0.31.0 cut from main's bin/swarm.sh, with the gate's output quoted and the behaviour changes every project gets listed (the gate, the retro step, swarm.sh retro), is the release-v0.31.0 story's, after retro-v0.31.0 (stage-gating's constraints).

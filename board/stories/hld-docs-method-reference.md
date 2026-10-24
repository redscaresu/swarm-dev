---
kind: docs
status: blocked
epic: hld-docs
depends_on: [plan-hld-command, plan-pr-grant, epic-guard-merge]
touches: [docs/method.md:planning chain, who does what and the skeptic line at :13, docs/reference.md:new HLD sections, lead_epics and epic guard lines, the --release row and the skeptic line near :240, bin/lib/build.sh:the hld/ remnant line near :871, bin/swarm.sh:skeptic policy comment and merge usage line, bin/lib/merge.sh:merge_pr header comment, docs/features.tsv:rows 3 and 46, tests/next_test.sh:the assertion near :491]
estimate_lines: 150
easy: false
---

# method.md and reference.md describe the HLD layer

Needs, from each depends_on: the shipped `/hld`, `/plan-hld`, `finish <hld>`, `grants` and the `planned:` line (plan-hld-command, plan-pr-grant), and the epic guard's refusals and `lead_epics` (epic-guard-merge). Describe what merged, read from the code on main, not from the plan.

- docs/method.md § The planning chain starts with the HLD step and its grants (epics, stories, merge, release). § Who does what names the `merge` and `release` grants as the exception to the user merging.
- docs/reference.md gains § Writing an HLD and § Decomposing an HLD, and names `lead_epics` and the epic guard.
- Each `hld/` remnant listed in board/epics/retro-and-shared-rules.md's Problem is now real or removed. docs/method.md:104, docs/reference.md:1355 and bin/lib/build.sh:871 stay, now true.
- plan-epic-lean-verify (#432) moved the per-story checks from skeptics to the critic, and skeptics now run only on `risk: high` stories. Bring the places that still say otherwise into line (its conductor logged them as out of scope): docs/method.md:13, the skeptic policy comment at bin/swarm.sh:331, docs/features.tsv:3,46 and tests/next_test.sh:491.
- The grant gates from merge-grant-gate (#426) and release-grant-gate (#428) are missing from swarm.sh's `merge` usage line, merge_pr's header comment (bin/lib/merge.sh, around :153) and docs/reference.md's `--release` row (around :1764): add them.
- Prose goes through the humanizer.

**Done when:**
- `grep -n "^## .*HLD" docs/reference.md` prints both new sections, and `grep -c "lead_epics\|epic guard" docs/reference.md` is at least 2.
- method.md's planning chain names `/hld` before `/plan-epic`, and § Who does what names both grants.
- `make test` passes, tests/doc_check_test.sh included.

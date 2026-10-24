---
kind: docs
status: blocked
epic: hld-docs
depends_on: [plan-hld-command, plan-pr-grant, epic-guard-merge]
touches: [docs/method.md, docs/reference.md, bin/lib/build.sh, bin/swarm.sh:skeptic policy comment, docs/features.tsv, tests/next_test.sh]
estimate_lines: 150
easy: false
---

# method.md and reference.md describe the HLD layer

Needs, from each depends_on: the shipped `/hld`, `/plan-hld`, `finish <hld>`, `grants` and the `planned:` line (plan-hld-command, plan-pr-grant), and the epic guard's refusals and `lead_epics` (epic-guard-merge). Describe what merged, read from the code on main, not from the plan.

- docs/method.md § The planning chain starts with the HLD step and its grants (epics, stories, merge, release). § Who does what names the `merge` and `release` grants as the exception to the user merging.
- docs/reference.md gains § Writing an HLD and § Decomposing an HLD, and names `lead_epics` and the epic guard.
- Each `hld/` remnant listed in board/epics/retro-and-shared-rules.md's Problem is now real or removed. docs/method.md:104, docs/reference.md:1355 and bin/lib/build.sh:871 stay, now true.
- plan-epic-lean-verify (#432) moved the per-story checks from skeptics to the critic, and skeptics now run only on `risk: high` stories. Bring the places that still say otherwise into line (its conductor logged them as out of scope): docs/method.md:13, the skeptic policy comment at bin/swarm.sh:331, docs/features.tsv:3,46 and tests/next_test.sh:491.
- Prose goes through the humanizer.

**Done when:**
- `grep -n "^## .*HLD" docs/reference.md` prints both new sections, and `grep -c "lead_epics\|epic guard" docs/reference.md` is at least 2.
- method.md's planning chain names `/hld` before `/plan-epic`, and § Who does what names both grants.
- `make test` passes, tests/doc_check_test.sh included.

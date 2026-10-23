---
kind: docs
status: blocked
epic: hld-docs
depends_on: [plan-hld-command, plan-pr-grant, epic-guard-merge]
touches: [docs/method.md, docs/reference.md, bin/lib/build.sh]
estimate_lines: 150
easy: false
---

# method.md and reference.md describe the HLD layer

Needs, from each depends_on: the shipped `/hld`, `/plan-hld`, `finish <hld>`, `grants` and the `planned:` line (plan-hld-command, plan-pr-grant), and the epic guard's refusals and `lead_epics` (epic-guard-merge). Describe what merged, read from the code on main, not from the plan.

- docs/method.md § The planning chain starts with the HLD step and its grants (epics, stories, merge, release). § Who does what names the `merge` and `release` grants as the exception to the user merging.
- docs/reference.md gains § Writing an HLD and § Decomposing an HLD, and names `lead_epics` and the epic guard.
- Each `hld/` remnant listed in board/epics/retro-and-shared-rules.md's Problem is now real or removed. docs/method.md:104, docs/reference.md:1355 and bin/lib/build.sh:871 stay, now true.
- Prose goes through the humanizer.

**Done when:**
- `grep -n "^## .*HLD" docs/reference.md` prints both new sections, and `grep -c "lead_epics\|epic guard" docs/reference.md` is at least 2.
- method.md's planning chain names `/hld` before `/plan-epic`, and § Who does what names both grants.
- `make test` passes, tests/doc_check_test.sh included.

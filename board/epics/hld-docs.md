---
status: active
parent: retro-and-shared-rules
depends_on: [plan-hld, epic-guard]
check: make test
---

# The docs describe the HLD layer as it is

The parent's goal 6.

**Done when:**
- docs/method.md § The planning chain puts the HLD step at the top, with its grants. § Who does what names the `merge` and `release` grants as the exception to the user merging.
- docs/reference.md has a § Writing an HLD and a § Decomposing an HLD, and names `lead_epics` and the epic guard.
- README.md's quick start and AGENTS.md's three-step run name `/hld` as the place a release's worth of work starts. AGENTS.md's never-merge rule under `merge = human` names the grants.
- docs/assets/swarm-flow.workflow.json has the HLD step. The light and dark PNGs are re-rendered from it with archify, by the builder.
- Each `hld/` remnant in the parent's Problem is now real or removed. docs/method.md:104, docs/reference.md:1355 and bin/lib/build.sh:871 stay, now real.
- tests/doc_check_test.sh passes.

**Out of scope:** writing the first HLD (the parent's **Your part**).
**Constraints:** the parent's. Human-facing prose goes through the humanizer.
**Your part:** none.

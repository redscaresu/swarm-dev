---
status: draft
hld: 2026-10-25-swarm-dev-0-28
stage: v0.31.0
depends_on: [rules-file, ladder-cost]
---

# The later story handover-and-usage ships

The later story handover-and-usage ships: swarm.sh handover carries .swarm without sessions, the board patch, the snapshot and RESTORE.md between machines, and a usage estimate warns in wait --lead at a user-set threshold, documented as an estimate (the lead's estimate undercounts Fable; /usage is the only truth, HLD Design § Top-rung cost), not a gate. HLD Goal 10 for this story (no Design part names it, so it rides in the last stage). This epic's /plan-epic PR adopts it (epic: set, status ready, touches as file:part).

**Done when:**
- The story's own Done when: tests/handover_test.sh shows handover holds .swarm without sessions, the board patch, the snapshot and RESTORE.md, and restoring gives the same board state (board/stories/handover-and-usage.md:12-18).
- wait --lead warns once when the usage estimate passes a threshold the user sets (a config key, in CONFIG_KEYS, validated, in reference.md's settings table, off by default); a fixture test for the Fable-weighted estimate and one for the warning, and one that no warning fires with the key unset.
- swarm.sh handover is a dispatch arm (`bin/swarm.sh:handover dispatch arm`) documented in reference.md and the usage header; doc_check passes; README says it is an estimate and names /usage as the truth.
- Appendix B's lead-handover note is the only infrafactory memory that moves into swarm-dev; the story records it.

**Out of scope:**
A usage gate on the ladder (HLD Non-goals); the retro command and gate (retro-report, retro-gate).

**Constraints:**
- bin/swarm.sh is touched as `bin/swarm.sh:handover dispatch arm`; retro-report touches `bin/swarm.sh:retro dispatch arm` and `bin/swarm.sh:usage header` (the header line for handover names retro-report's header story in depends_on).
- Ship switched off: the threshold key defaults off (docs/reference.md:328-333).
- Never read a credential file; the snapshot carries no sessions (the story's rule).
- bash 3.2, shellcheck, loose_match_test, make test; humanizer over README and docs prose.
- Order: retro-report's retro-v0.31.0 story goes after this epic's stories; this epic's usage-header line goes after retro-report's header story.

**Areas:** bin/swarm.sh:handover dispatch arm, bin/lib/ (handover and usage helpers), bin/lib/lifecycle.sh:wait --lead usage warning, bin/lib/reports.sh:usage estimate, docs/reference.md:handover and settings table, README.md, board/stories/handover-and-usage.md (adopted), tests/ (handover, wait_lead)

**Your part:**
None beyond the user setting the threshold key if they want the warning.

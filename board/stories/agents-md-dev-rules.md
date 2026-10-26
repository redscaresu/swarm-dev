---
kind: docs
status: blocked
epic: dev-rules-docs
depends_on: [env-line-docs-patch, owner-findings-rounds]
needs: [env-line-docs-patch: its env: line fix in AGENTS.md's Rules that are not negotiable (shared part), owner-findings-rounds (review-loop): its AGENTS.md review-agent edit, which these sections follow]
touches: [AGENTS.md:Rules that are not negotiable, AGENTS.md:Working on this repository]
estimate_lines: 40
easy: true
---

# AGENTS.md: the removal rule, the patch cadence, docs move with behaviour, the development rules

Uses env-line-docs-patch's corrected env: line (same AGENTS.md list) and review-loop's owner-findings-rounds' AGENTS.md edit (epic Constraints: these go after it). AGENTS.md gains, each once: nothing a board sets is removed until every board the user runs is checked, and a removed key warns and loads for a release (tests/removed_test.sh:30-48 pins the second half); a fix to the swarm's own loop ships as a patch release soon after it merges; docs move with behaviour in the same PR; and Appendix C's development rules: tests only through make (or scripts/select-tests.sh --run), unset SWARM_PROJECT and run no reports over days on the real repo, stress at most 4 CPUs and torn down, mutation proofs in copies. Put each under 'Working on this repository' or 'Rules that are not negotiable'; drop a line that already says it.

**Done when:**
- AGENTS.md states each of the seven rules once; the PR body lists each with its AGENTS.md line.
- tests/doc_check_test.sh passes.

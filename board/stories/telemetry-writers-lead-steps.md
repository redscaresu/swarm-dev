---
kind: lead
status: blocked
epic: telemetry-writers
depends_on: [intervene-cause, telemetry-hooks]
needs: [intervene-cause: INTERVENE_CAUSES and the three-argument form (its merge starts the cause step)]
touches: []
estimate_lines: 0
easy: false
---

# Lead: merge the hooks PR by hand, and give a cause on every intervene

From intervene-cause it uses INTERVENE_CAUSES and the form `swarm.sh intervene <kind> <cause> "<line>"`. The epic's Your part, steps 1 and 3. **You:** when wait --lead or status shows telemetry-hooks' PR held as a protected-path change, read its diff and merge it by hand. **You:** from the day intervene-cause merges, give a cause on every swarm.sh intervene; use `other` only when none fits, and say what happened in the line.

**Done when:**
- telemetry-hooks' PR is merged by the user.
- Every lead-hand and user-caught incident line written after intervene-cause merged carries cause=.
- The user merged telemetry-hooks' PR, and after it the old intervene form exits 1.

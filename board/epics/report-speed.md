---
status: active
parent: less-noise
hld: 2026-10-25-swarm-dev-0-28
stage: v0.29.0
depends_on: []
---

# status, next and dash finish within a time limit, and flow reports their run times

A read deadline for the three reports, each adopting it with a test, and their run times logged apart from events.tsv and reported by flow.

A child of less-noise, split at planning (2026-10-26). Its stories were planned with the parent; the parent's Out of scope, Constraints and Your part apply.

**Done when:**
- report-deadline: A deadline helper for reads in status, next and dash
- status-time-limit: swarm.sh status finishes within the report deadline
- next-time-limit: swarm.sh next finishes within the report deadline, and never cuts a conductor start
- dash-time-limit: swarm.sh dash finishes within the report deadline, and dash --watch draws at once
- report-run-times: flow reports how long status, next and dash took

**Areas:** see each story's touches.

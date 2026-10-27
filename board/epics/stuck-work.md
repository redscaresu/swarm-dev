---
status: active
parent: less-noise
hld: 2026-10-25-swarm-dev-0-28
stage: v0.29.0
depends_on: []
---

# wait --lead wakes the lead for stuck work and idle capacity

Prompts, dialogs, manual mode, unmerged and conflicting PRs, and idle capacity reach the lead through wait --lead, status and dash, and tell gets through a cleared dialog.

A child of less-noise, split at planning (2026-10-26). Its stories were planned with the parent; the parent's Out of scope, Constraints and Your part apply.

**Done when:**
- pane-prompt-classifier: panes.py tells a pane stuck on a prompt, a dialog, manual mode, a login or an API error
- idle-lines-in-lead-queue: wait --lead, status and dash carry next's idle: lines
- stuck-work-watch: wait --lead wakes the lead for an agent stuck on a prompt, a dialog or manual mode
- unmerged-conflict-lines: wait --lead names a reviewed PR left unmerged, and a PR that conflicts with its base
- tell-reads-blocked-pane: tell checks the pane before refusing an agent listed as blocked or waiting
- concurrency-check: next's idle dependency line goes by touches part and reads needs
- idle-ready-no-build: idle: a ready story with no build past queue_minutes
- idle-epic-lines: idle: an epic that can start, and an active epic with no plan running
- These stories ship first, in the v0.28.1 patch, so the rest of the v0.29.0 build runs with them.

**Areas:** see each story's touches.

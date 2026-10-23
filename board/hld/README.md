# High-level designs

The top of the planning chain: **HLD → epics → stories → built in parallel**. An HLD is written
with the user, on the most capable model, before any work is scoped.

File: `docs/hld/YYYY-MM-DD-<slug>.md` — the day it was started, then a slug. No spaces: Obsidian
writes a space in a link as `%20`, which the link test cannot resolve. Start one with
`/hld <title>`.

```
---
title: <Title>
date: YYYY-MM-DD
status: draft | agreed | superseded
grants: []
---

# <Title>

## Problem            what is wrong or missing, with evidence (file:line, runs, PRs)
## Goals              what must be true when this is done
## Non-goals          what this deliberately will not do
## Current state      how it works today
## Design             the proposal
## Alternatives       what else was considered, and why not
## Risks and safety   cost, production exposure, ADRs and gates it touches
## Rollout            order, and what can ship on its own
## Open questions     what is not decided yet
## Epics              one link per epic planned from it
```

An HLD is `agreed` before any epic is planned from it; each epic links back with
`hld: <file-name-without-.md>`. Only the user sets `superseded`, by hand, when a later HLD replaces it.

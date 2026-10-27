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
`hld: <file-name-without-.md>`. `/plan-hld` plans it, and its board PR adds `planned: <date>` to the
front matter, the day it was planned. Nothing else sets it, so the skeleton above has no such line.
Only the user sets `superseded`, by hand, when a later HLD replaces it.

`grants:` lists what the lead may do under this HLD without asking the user, once it is `agreed`:

- `epics`: plan epics from the HLD.
- `stories`: write an epic's stories and open the board PR without asking (`/plan-epic`).
- `merge`: merge a story PR or board PR under the HLD, even with `merge = human`.
- `release`: merge a release PR whose stories since the last tag are all under HLDs that grant it.

An absent `grants:` means none. Only the user sets it. `swarm.sh grants <story | epic | hld | PR URL>`
prints the agreed HLD over an item and its grants, or `none`.

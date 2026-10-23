---
status: active
parent: retro-and-shared-rules
depends_on: []
check: make test
---

# An HLD can be written with the user and agreed

The parent's goal 1 (board/epics/retro-and-shared-rules.md), and its Problem's last bullet.

**Done when:**
- `/hld <title>` (`commands/hld.md`, full name `/swarm-dev:hld`) creates `<board>/hld/YYYY-MM-DD-<slug>.md` as `status: draft` from a template with the ten sections (Problem, Goals, Non-goals, Current state, Design, Alternatives, Risks and safety, Rollout, Open questions, Epics) and a `grants: []` line. It opens a co-author pane on the most capable model. When the user says the draft is ready it starts a reviewer, whose brief attacks the draft's `grants:` as a risk, and it sets `status: agreed` only when the user agrees in that pane, the way commands/epic.md does. `/hld` with no title resumes the draft in progress.
- `swarm.sh init` writes `<board>/hld/README.md` with the template and the statuses `draft`, `agreed` and `superseded`, and templates/docs/Board.base gets an HLD view. A test checks that an init'd board has both.
- The roles `hld`, `hld-review` and `hld-lead` are in `ROLE_GROUPS` (bin/swarm.sh:315), and `swarm.sh policy <role>` answers for each one. A test covers it.
- `swarm.sh next` lists a draft HLD under waiting on you, the way it lists a draft epic.

**Out of scope:** grants (hld-grants), decomposing an HLD (plan-hld), the epic guard (epic-guard), the user docs (hld-docs).
**Constraints:** the parent's. bash 3.2. Only the user changes an HLD's `status`.
**Your part:** none.

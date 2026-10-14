---
kind: code
status: blocked
blocked_by: [wire-escalate-role]
epic: fable-on-call
depends_on: [wire-escalate-role]
touches: [tests/roles_test.sh (new)]
---

# A structural test that every ROLE_GROUPS role is started by a command, a start_agent call or the role function

New tests/roles_test.sh. Roles from ROLE_GROUPS (bin/swarm.sh:272). A role is reached when: a `swarm.sh agent` line in commands/*.md passes it literally (hld, hld-review: commands/hld.md:38,44); a commands/*.md file with a `swarm.sh agent ... <role>` line names it as role `x` (survey, lead, skeptic, critic, codex, hld-lead: plan-epic.md:18,35-77, plan-hld.md:14-46); a start_agent call in bin/swarm.sh passes it literally (conduct, :1779); or `swarm.sh _role` returns it for a fixture story on a throwaway board (code, code-risky, code-sonnet with sonnet_share, docs, chore, verify, escalate with attempts: 2). Comments and method sentences never count. It fails naming each unreached role.

**Done when:**
- tests/roles_test.sh passes on the PR head.
- The PR shows it red, naming escalate, on db657b7's shape: the head with story_role's escalate arm removed.
- It fails, naming the role, when a role is added to ROLE_GROUPS and policy() with no caller, and when commands/hld.md's hld-review agent line is removed.
- shellcheck tests/*.sh and every tests/*_test.sh pass.

**From review (binding; overrides the scope above where they differ):**
- Runs on macOS's bash 3.2: no mapfile, no associative arrays (AGENTS.md).

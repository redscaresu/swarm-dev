---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/merge.sh:merge --board checks, commands/epic.md:step 5, commands/swarm.md, skills/swarm-dev/SKILL.md, tests/merge_test.sh, docs/reference.md:Merging]
easy: false
estimate_lines: 120
---

# A board merge cannot make an epic active unless the user agreed it through /swarm-dev:epic

User, 2026-10-23: the lead wrote the 0.27 epic retro-and-shared-rules alone and merged it as `status: active` (#399). The user had asked to plan it together. An active epic with no stories can be planned by `next` without the user, and nothing in swarm-dev stopped it. The lead set it back to draft by hand (#400). The user asked for this to be prevented in swarm-dev itself, for every project, in this release.

- **commands/epic.md step 5.** When `D/agreed` exists and it sets `status: active`, it also writes `agreed: <YYYY-MM-DD>` into the epic's front matter.
- **merge --board.** It refuses a board PR whose diff makes any `epics/*.md` active, either a new file with `status: active` or a status changed to `active`, unless the epic at the PR's head has an `agreed:` line and `.swarm/epic-<slug>/agreed` exists in the project. The refusal names the epic and says: run `/swarm-dev:epic <slug>`, so the user co-writes and agrees it. A child epic that /plan-epic writes for a large epic (`parent:` set) is exempt, because its parent was agreed. The guard also runs in `board-pr open`, so the PR isn't opened at all.
- **commands/swarm.md and skills/swarm-dev/SKILL.md** say: the lead never writes an epic's goals, Done when or status. Work found in a retro or a request goes into a draft, and `/swarm-dev:epic` runs with the user.

**Done when:**
- tests/merge_test.sh, with a stub gh: a board PR adding `epics/x.md` with `status: active` and no `agreed:` line is refused with the `/swarm-dev:epic x` hint. A draft-to-active flip with `agreed:` and the local marker merges. A child epic with `parent:` merges without the marker. A board PR that changes nothing about epic status is untouched.
- commands/epic.md step 5 writes the `agreed:` line, and the lead's rules in commands/swarm.md and SKILL.md say the lead never activates an epic.

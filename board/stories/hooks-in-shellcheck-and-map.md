---
kind: chore
status: ready
depends_on: []
touches: [.github/workflows/ci.yml:shellcheck step, Makefile:lint target, AGENTS.md:Working on this repository tree]
estimate_lines: 30
easy: true
---

# CI shellchecks hooks/*.sh, and AGENTS.md's map lists the new hook files

CI's shellcheck step covers no `hooks/*.sh`, which was true before #515 too (backlog conductor report, 2026-10-25). #515 also added `hooks/user-caught-reminder.sh` and `hooks/lead-session.sh`, which AGENTS.md's repo map (its `hooks/` line, around :119) does not list. Add hooks/*.sh to the shellcheck step and the Makefile's lint, fix anything it flags, and add the two files to the map. agents-md-test-selection (test-speed) also edits AGENTS.md:Working on this repository tree; if it is open when this builds, merge after it.

**Done when:**
- CI's shellcheck step and `make lint` run on hooks/*.sh, and pass.
- AGENTS.md's map lists both new hook files.

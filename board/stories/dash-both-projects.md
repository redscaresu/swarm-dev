---
kind: code
status: ready
epic: leaner-faster-swarm
depends_on: []
touches: [bin/swarm.sh:dash, dash_size, dash_watch, dash_reexec, usage header: dash line, docs/dash.md:two projects paragraph, tests/dash_projects_test.sh, tests/dash_reexec_test.sh]
---

# One `swarm.sh dash --project <dir> --project <dir>` shows both projects, once and with --watch

dash (bin/swarm.sh:4007-4035) takes a repeatable `--project <dir>`. With one or more, it first checks every dir (each needs .claude/swarm/config and a board) and fails naming the first bad one before it draws anything, and it skips the calling project's own board check (:4022), so it runs from any git repo. It then renders each project's frame in turn, headed by the project's name, by running this script again with SWARM_PROJECT=<dir>. PROJECT_DIR, BOARD and the logs are globals set at startup, so dash_render does not change. Each child gets the parent's colour and its share of the height through env that dash and dash_size (:4037-4052) honour when set: DASH_COLOR (dash turns colour on only when stdout is a tty, :4025-4028, which a child inside $(...) never is), and DASH_W and DASH_H, DASH_H being the parent's height divided by the number of projects. With --watch, dash_watch (:4188-4241) redraws every project each tick as one frame, so the in-place repaint (:4219-4223) neither scrolls nor flickers, and dash_reexec (:4269-4284) passes every --project through. Without --project nothing changes. The header's dash line (:21) shows the flag. docs/dash.md: a new paragraph right after the opening paragraph (:3-11). Tests in a new tests/dash_projects_test.sh. bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- tests/dash_projects_test.sh: with two throwaway projects, `dash --project a --project b`, run from a git repo that has no board, prints a's frame and then b's, each headed by its name and listing only its own board's epics.
- `dash --project a --project /nonexistent` exits non-zero naming /nonexistent, and prints no frame for a.
- With DASH_H=40 and two projects, neither frame is over 20 lines; with DASH_COLOR set, a frame drawn off a terminal carries colour codes, and without it none.
- Off a terminal, `dash --watch 1 --project a --project b`, with b's board changed while it runs, prints both projects' frames on each tick that changed.
- tests/dash_reexec_test.sh: the re-exec keeps both --project flags, and tests/dash_test.sh passes unchanged.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.

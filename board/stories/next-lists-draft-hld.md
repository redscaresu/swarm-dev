---
kind: code
status: ready
epic: hld-command
depends_on: []
touches: [bin/lib/board.sh:waiting_on_user, bin/lib/dash_render.py, tests/next_test.sh, tests/dash_test.sh]
estimate_lines: 70
easy: true
---

# next lists a draft HLD under waiting on you

waiting_on_user (bin/lib/board.sh:622-626) walks `board epics` only. It gains a walk over `board hld` that prints `  draft hld: <file name>, run /hld <file name>` for each `status: draft` HLD (never the README). next_step adds no `hld` arm: the plan-hld epic adds the agreed-HLD arm.

bin/lib/dash_render.py skips `draft epic: ` waiting lines, since the board walk gives each its own needs-you row. Do the same for `draft hld: `: skip the waiting line, and give a draft HLD (`b[0]=="hld"`, status draft) its own needs-you row. The old row is at `git show 47a8ced9 -- bin/lib/dash_render.py`.

tests/next_test.sh:62-66 asserts that HLD files are ignored. Change the draft case: next now prints `gate` with a `draft hld:` line. The agreed and superseded cases still print `done`.

**Done when:**
- tests/next_test.sh: a draft HLD gives `gate` with `draft hld: <name>, run /hld <name>`; an agreed one and a superseded one give `done`; board/hld/README.md is never listed.
- A dash test shows a draft HLD as one needs-you row and not also as a waiting line.
- `make test` passes.

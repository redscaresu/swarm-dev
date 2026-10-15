---
kind: code
status: ready
touches: [bin/swarm.sh:dash, tests/dash_test.sh]
---

# dash in a folder with no board says so instead of "nothing needs you"

Run from a folder with no board (no `<board>/stories/README.md`, e.g. a scratch repo named `repo`), `swarm.sh dash` draws "nothing needs you" and `next done`. That reads as a finished board. It should print one line saying there is no board here and how to start one (`swarm.sh init`), and exit non-zero, the same way `next` behaves outside a project.

**Done when:**
- tests/dash_test.sh: `dash` run in a temp git repo with no board prints a line containing "no board" and exits non-zero; it does not contain "nothing needs you".
- `dash` on a board with nothing to do still prints "nothing needs you" (existing test unchanged).
- The PR shows the new check failing with its code removed; shellcheck and every tests/*_test.sh pass.
